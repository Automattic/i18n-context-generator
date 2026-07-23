# frozen_string_literal: true

require_relative 'context_extractor/source_filters'
require_relative 'context_extractor/run_logging'
require_relative 'context_extractor/source_entries'
require_relative 'context_extractor/translation_filters'
require_relative 'context_extractor/cache_identity'
require_relative 'context_extractor/extraction_result'
require_relative 'context_extractor/workflow'

module I18nContextGenerator
  # Main orchestrator that parses translation files, searches source code for usages,
  # sends context to the LLM, and writes results via the configured writer.
  class ContextExtractor
    include Writers::Helpers
    include SourceFilters
    include RunLogging
    include SourceEntries
    include TranslationFilters
    include CacheIdentity
    include Workflow

    attr_reader :results, :errors, :metrics

    def initialize(config, log_output: nil, structured_output: nil, patch_output: nil,
                   quiet: false, progress: true)
      @config = config
      @configured_log_output = log_output
      @structured_output = structured_output
      @patch_output = patch_output
      @quiet = quiet
      @progress_enabled = progress && !quiet
      @results = Concurrent::Array.new
      @errors = Concurrent::Array.new
      @metrics = RunMetrics.from([], provider: @config.provider, model: resolved_model)

      # Defer initialization of expensive resources
      @searcher = nil
      @llm = nil
      @cache = nil
      @supplemental_context = nil
    end

    def run
      @config.validate!
      @platform = PlatformValidator.new(@config).validate!

      entries = load_entries
      entries = filter_entries(entries) if @config.key_filter
      entries = filter_by_diff(entries) if @config.diff_base && translation_backed_discovery?
      entries = filter_by_range(entries) if @config.start_key || @config.end_key

      if entries.empty?
        log_empty_entries_message
        return
      end

      log_loaded_entries(entries.size)

      return if pre_extraction_stage_handled?(entries)

      # Provider construction validates credentials. Resolve it once on the
      # caller thread so a configuration error is reported once instead of
      # being duplicated by every worker.
      supplemental_context
      llm
      process_entries(entries)
      @metrics = RunMetrics.from(@results, provider: @config.provider, model: resolved_model)

      deliver_results

      log "Errors: #{@errors.size}" if @errors.any?
      log_metrics
    end

    private

    def searcher
      @searcher ||= Searcher.new(
        source_paths: @config.source_paths,
        ignore_patterns: @config.ignore_patterns,
        context_lines: @config.context_lines,
        platform: @platform,
        swift_functions: @config.swift_functions
      )
    end

    def llm
      @llm ||= LLM::Client.for(@config.provider, endpoint: @config.endpoint)
    end

    def cache
      @cache ||= Cache.new(enabled: !@config.no_cache, directory: @config.cache_dir)
    end

    def supplemental_context
      @supplemental_context ||= SupplementalContext.load(
        files: @config.context_files,
        runtime: @config.supplemental_context
      )
    end

    def load_translations
      return @load_translations if defined?(@load_translations)

      entries = @config.translations.flat_map do |path|
        parser = Parsers::Base.for(path, locale: @config.translation_locales[path])
        parser.parse(path)
      end

      @load_translations = validate_translation_entries(entries)
    rescue I18nContextGenerator::Error
      raise
    rescue StandardError => e
      raise Error, "Failed to load translations: #{e.message}"
    end

    def filter_entries(entries)
      configured_patterns = if @config.key_filter.is_a?(Array)
                              @config.key_filter
                            else
                              @config.key_filter.split(',')
                            end
      patterns = configured_patterns.map do |pattern|
        escaped = Regexp.escape(pattern.strip).gsub('\*', '.*')
        Regexp.new("^#{escaped}$")
      end

      entries.select do |entry|
        patterns.any? { |p| entry.key.match?(p) }
      end
    end

    def filter_by_range(entries)
      start_idx = 0
      end_idx = entries.size - 1

      if @config.start_key
        found_idx = entries.find_index { |e| e.key == @config.start_key }
        raise Error, "start_key not found: #{@config.start_key}" unless found_idx

        start_idx = found_idx
      end

      if @config.end_key
        found_idx = entries.rindex { |e| e.key == @config.end_key }
        raise Error, "end_key not found: #{@config.end_key}" unless found_idx

        end_idx = found_idx
      end

      raise Error, 'start_key must not come after end_key' if start_idx > end_idx

      range_info = []
      range_info << "from '#{@config.start_key}'" if @config.start_key
      range_info << "to '#{@config.end_key}'" if @config.end_key
      log "Filtering #{range_info.join(' ')}: keys #{start_idx + 1} to #{end_idx + 1}"

      entries[start_idx..end_idx]
    end

    def process_entries(entries)
      # Results expose changed source locations even during translation-backed
      # discovery. Resolve the diff once on the caller thread before workers can
      # race to initialize the lazy filter.
      source_line_filter if @config.diff_base

      progress = build_progress(entries.size)

      # Use a thread pool for concurrent processing
      pool = Concurrent::FixedThreadPool.new(@config.concurrency)

      entries.each do |entry|
        pool.post do
          result = process_entry(entry)
          @results << result
          @errors << result if result.error
        rescue StandardError => e
          # Capture errors as results so they're visible in output
          result = ExtractionResult.new(
            key: entry.key,
            text: entry.text,
            description: 'Processing failed',
            source_file: entry.source_file,
            translation_key: translation_key_for(entry),
            changed_translation_locations: changed_translation_locations_for(entry),
            status: :error,
            error: e.message
          )
          @results << result
          @errors << result
        ensure
          progress&.advance(key: truncate(entry.key, 40))
        end
      end

      pool.shutdown
      pool.wait_for_termination
      log if progress # New line after progress bar
    end

    def build_progress(total)
      return unless @progress_enabled

      TTY::ProgressBar.new(
        '[:bar] :current/:total :percent :eta :key',
        total: total,
        width: 30,
        output: log_output
      )
    end

    def process_entry(entry)
      # Search for key usage in code first — needed for both cache key and LLM prompt
      resource_type = entry.metadata&.dig(:resource_type)
      matches = if resource_type
                  searcher.search(entry.key, resource_type: resource_type)
                else
                  searcher.search(entry.key)
                end
      comment = @config.include_translation_comments ? entry.metadata&.dig(:comment) : nil

      if matches.empty?
        return ExtractionResult.new(
          key: entry.key,
          text: entry.text,
          description: 'No usage found in source code',
          source_file: entry.source_file,
          translation_key: translation_key_for(entry),
          changed_translation_locations: changed_translation_locations_for(entry),
          status: :no_usage,
          locations: []
        )
      end

      # Limit matches to avoid huge prompts
      matches = matches.first(@config.max_matches_per_key)
      context_sources = supplemental_context

      cache_ctx = cache_context(entry, matches, comment, context_sources)

      # Check cache with match context included
      cached = cache.get(entry.key, entry.text, context: cache_ctx)
      return cached_extraction_result(entry, cached, matches) if cached && !(cached[:error] || cached['error'])

      # Get context from LLM
      llm_result = llm.generate_context(
        key: entry.key,
        text: entry.text,
        matches: matches,
        model: @config.model,
        comment: comment,
        include_file_paths: @config.include_file_paths,
        redact_prompts: @config.redact_prompts,
        max_prompt_chars: @config.max_prompt_chars,
        supplemental_context: context_sources
      )

      result_locations = result_locations_for(entry, matches)
      result = ExtractionResult.new(
        key: entry.key,
        text: entry.text,
        description: llm_result.description,
        source_file: entry.source_file,
        ui_element: llm_result.ui_element,
        tone: llm_result.tone,
        max_length: llm_result.max_length,
        confidence: llm_result.confidence,
        ambiguity_reason: llm_result.ambiguity_reason,
        request_count: llm_result.request_count,
        input_tokens: llm_result.input_tokens,
        output_tokens: llm_result.output_tokens,
        retries: llm_result.retries,
        locations: result_locations,
        **changed_location_attributes_for(entry, result_locations),
        translation_key: translation_key_for(entry),
        changed_translation_locations: changed_translation_locations_for(entry),
        status: llm_result.error ? :error : :success,
        error: llm_result.error
      )

      unless result.error
        cache.set(
          entry.key,
          entry.text,
          result.to_h.except(
            :source_file, :changed_locations, :changed_location_groups, :changed_translation_locations,
            :cache_hit, :request_count, :input_tokens, :output_tokens, :retries
          ),
          context: cache_ctx
        )
      end
      result
    end

    def cached_extraction_result(entry, cached, matches)
      attributes = cached.transform_keys(&:to_sym).except(
        :source_file, :locations, :changed_locations, :changed_location_groups,
        :translation_key, :changed_translation_locations,
        :cache_hit, :request_count, :input_tokens, :output_tokens, :retries
      )
      locations = result_locations_for(entry, matches)
      ExtractionResult.new(
        source_file: entry.source_file,
        locations: locations,
        **changed_location_attributes_for(entry, locations),
        translation_key: translation_key_for(entry),
        changed_translation_locations: changed_translation_locations_for(entry),
        cache_hit: true,
        **attributes
      )
    end

    def write_output
      writer = case @config.output_format.to_s.downcase
               when 'json'
                 Writers::JsonWriter.new
               else
                 Writers::CsvWriter.new
               end

      writer.write(
        @results,
        @config.output_path,
        metrics: @metrics,
        output: @structured_output || $stdout
      )
    end

    def write_back_to_source
      @config.translations.each do |path|
        next unless File.exist?(path)

        writer = source_writer_for(path)
        next unless writer

        relevant_results = @results.select { |result| result_matches_source_path?(result, path) }
        next if relevant_results.empty?

        updated = writer.write(relevant_results, path)
        log "Updated #{path} with context comments" if updated
      end
    end

    def write_back_to_code
      updated_count = 0
      results_by_key = build_results_by_key_for_code_write_back
      return if results_by_key.empty?

      swift_files_for_write_back.each do |swift_file|
        if swift_writer.update_file(swift_file, results_by_key)
          updated_count += 1
          log "Updated #{swift_file} with context comments"
        end
      end

      log "Updated #{updated_count} Swift files with context comments" if updated_count.positive?
    end

    def validate_translation_entries(entries)
      invalid_entry = entries.find do |entry|
        !entry.key.is_a?(String) || entry.key.empty? ||
          !entry.text.is_a?(String) ||
          !entry.source_file.is_a?(String) || entry.source_file.empty?
      end
      if invalid_entry
        source = invalid_entry.source_file || 'unknown source'
        raise Error, "Invalid translation entry in #{source}: key, text, and source file must be strings"
      end

      grouped = entries.group_by { |entry| [File.expand_path(entry.source_file), entry.key] }
      conflicts = grouped.filter_map do |(source_file, key), duplicates|
        "#{source_file}:#{key}" if duplicates.map(&:text).uniq.size > 1
      end
      raise Error, "Conflicting duplicate translation keys: #{conflicts.join(', ')}" if conflicts.any?

      entries.uniq { |entry| [File.expand_path(entry.source_file), entry.key, entry.text] }
    end

    def build_results_by_key_for_code_write_back
      @results
        .sort_by { |result| [translation_source_priority(result.source_file), result.key] }
        .each_with_object({}) do |result, lookup|
          next unless writable_result?(result)

          lookup[result.key] ||= result
        end
    end

    def translation_source_priority(source_file)
      return @config.translations.size unless source_file

      index = @config.translations.index(source_file)
      index || @config.translations.size
    end

    def source_writer_for(path)
      ext = File.extname(path).downcase

      case ext
      when '.strings'
        Writers::StringsWriter.new(
          context_prefix: @config.context_prefix,
          context_mode: @config.context_mode
        )
      when '.xcstrings'
        Writers::XcstringsWriter.new(
          context_prefix: @config.context_prefix,
          context_mode: @config.context_mode
        )
      when '.xml'
        if FileClassifier.android_translation_file?(path)
          Writers::AndroidXmlWriter.new(
            context_prefix: @config.context_prefix,
            context_mode: @config.context_mode
          )
        end
      end
    end

    def truncate(str, length, omission: '...')
      return str if str.length <= length

      "#{str[0, length - omission.length]}#{omission}"
    end
  end
end
