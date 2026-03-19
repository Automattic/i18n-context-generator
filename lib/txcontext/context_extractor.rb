# frozen_string_literal: true

module Txcontext
  # Main orchestrator that parses translation files, searches source code for usages,
  # sends context to the LLM, and writes results via the configured writer.
  class ContextExtractor
    include Writers::Helpers

    # Result for a single translation key
    ExtractionResult = Data.define(:key, :text, :description, :source_file, :ui_element, :tone,
                                   :max_length, :locations, :error) do
      def initialize(key:, text:, description:, source_file: nil, ui_element: nil, tone: nil,
                     max_length: nil, locations: [], error: nil)
        super
      end

      def to_h
        {
          key: key,
          text: text,
          description: description,
          source_file: source_file,
          ui_element: ui_element,
          tone: tone,
          max_length: max_length,
          locations: locations,
          error: error
        }
      end
    end

    attr_reader :results, :errors

    def initialize(config)
      @config = config
      @results = Concurrent::Array.new
      @errors = Concurrent::Array.new

      # Defer initialization of expensive resources
      @searcher = nil
      @llm = nil
      @cache = nil
    end

    def run
      PlatformValidator.new(@config).validate!

      entries = load_translations
      entries = filter_entries(entries) if @config.key_filter
      entries = filter_by_diff(entries) if @config.diff_base
      entries = filter_by_range(entries) if @config.start_key || @config.end_key

      if entries.empty?
        if @config.diff_base
          puts "No changed translation keys found since #{@config.diff_base}."
        else
          puts 'No translation entries found.'
        end
        return
      end

      puts "Loaded #{entries.size} translation keys"
      puts "(filtered to changes since #{@config.diff_base})" if @config.diff_base

      if @config.dry_run
        puts "\nDry run - would process these keys:"
        entries.first(20).each { |e| puts "  - #{e.key}: #{truncate(e.text, 50)}" }
        puts "  ... and #{entries.size - 20} more" if entries.size > 20
        return
      end

      process_entries(entries)

      if @config.output_path
        write_output
        puts "\nWrote #{@results.size} results to #{@config.output_path}"
      end

      write_back_to_source if @config.write_back

      write_back_to_code if @config.write_back_to_code

      puts "Errors: #{@errors.size}" if @errors.any?
    end

    private

    def searcher
      @searcher ||= Searcher.new(
        source_paths: @config.source_paths,
        ignore_patterns: @config.ignore_patterns,
        context_lines: @config.context_lines
      )
    end

    def llm
      @llm ||= LLM::Client.for(@config.provider)
    end

    def cache
      @cache ||= Cache.new(enabled: !@config.no_cache)
    end

    def load_translations
      @config.translations.uniq.flat_map do |path|
        unless File.exist?(path)
          warn "Translation file not found: #{path}"
          next []
        end

        parser = Parsers::Base.for(path)
        parser.parse(path)
      end
    end

    def filter_entries(entries)
      patterns = @config.key_filter.split(',').map do |pattern|
        escaped = Regexp.escape(pattern.strip).gsub('\*', '.*')
        Regexp.new("^#{escaped}$")
      end

      entries.select do |entry|
        patterns.any? { |p| entry.key.match?(p) }
      end
    end

    def filter_by_diff(entries)
      git_diff = GitDiff.new(base_ref: @config.diff_base)
      changed_keys = git_diff.changed_keys(@config.translations)

      if changed_keys.empty?
        puts "No changes detected in translation files since #{@config.diff_base}"
        return []
      end

      puts "Found #{changed_keys.size} changed keys in git diff"

      entries.select do |entry|
        changed_keys.include?(entry.key) || changed_keys.include?(android_base_key(entry.key))
      end
    end

    # Extract the base resource name from composite Android keys
    # e.g., "post_likes_count:one" -> "post_likes_count"
    #        "days_of_week[0]"     -> "days_of_week"
    def android_base_key(key)
      key.sub(/:[a-z]+$/, '').sub(/\[\d+\]$/, '')
    end

    def filter_by_range(entries)
      start_idx = 0
      end_idx = entries.size - 1

      if @config.start_key
        found_idx = entries.find_index { |e| e.key == @config.start_key }
        if found_idx
          start_idx = found_idx
        else
          puts "Warning: start_key '#{@config.start_key}' not found, starting from beginning"
        end
      end

      if @config.end_key
        found_idx = entries.find_index { |e| e.key == @config.end_key }
        if found_idx
          end_idx = found_idx
        else
          puts "Warning: end_key '#{@config.end_key}' not found, processing to end"
        end
      end

      range_info = []
      range_info << "from '#{@config.start_key}'" if @config.start_key
      range_info << "to '#{@config.end_key}'" if @config.end_key
      puts "Filtering #{range_info.join(' ')}: keys #{start_idx + 1} to #{end_idx + 1}"

      entries[start_idx..end_idx]
    end

    def process_entries(entries)
      # Ensure output is not buffered
      $stdout.sync = true

      progress = TTY::ProgressBar.new(
        '[:bar] :current/:total :percent :eta :key',
        total: entries.size,
        width: 30,
        output: $stdout
      )

      # Use a thread pool for concurrent processing
      pool = Concurrent::FixedThreadPool.new(@config.concurrency)
      semaphore = Concurrent::Semaphore.new(@config.concurrency)
      current_key = Concurrent::AtomicReference.new('')

      entries.each do |entry|
        pool.post do
          semaphore.acquire
          begin
            current_key.set(truncate(entry.key, 40))
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
              error: e.message
            )
            @results << result
            @errors << result
          ensure
            semaphore.release
            progress.advance(key: current_key.get)
          end
        end
      end

      pool.shutdown
      pool.wait_for_termination
      puts # New line after progress bar
    end

    def process_entry(entry)
      # Search for key usage in code first — needed for both cache key and LLM prompt
      matches = searcher.search(entry.key)
      comment = @config.include_translation_comments ? entry.metadata&.dig(:comment) : nil

      if matches.empty?
        return ExtractionResult.new(
          key: entry.key,
          text: entry.text,
          description: 'No usage found in source code',
          source_file: entry.source_file,
          locations: []
        )
      end

      # Limit matches to avoid huge prompts
      matches = matches.first(@config.max_matches_per_key)

      # Build a cache context digest from all prompt-shaping inputs so the cache
      # invalidates when source code, comments, or model change
      cache_ctx = [
        matches.map { |m| "#{m.file}:#{m.line}:#{m.match_line}:#{m.enclosing_scope}:#{m.context}" }.sort.join("\0"),
        "comment:#{comment}",
        "provider:#{@config.provider}",
        "model:#{@config.model}",
        "include_file_paths:#{@config.include_file_paths}",
        "redact_prompts:#{@config.redact_prompts}"
      ].join("\n")

      # Check cache with match context included
      if (cached = cache.get(entry.key, entry.text, context: cache_ctx))
        return ExtractionResult.new(source_file: entry.source_file, **cached.transform_keys(&:to_sym))
      end

      # Get context from LLM
      llm_result = llm.generate_context(
        key: entry.key,
        text: entry.text,
        matches: matches,
        model: @config.model,
        comment: comment,
        include_file_paths: @config.include_file_paths,
        redact_prompts: @config.redact_prompts
      )

      result = ExtractionResult.new(
        key: entry.key,
        text: entry.text,
        description: llm_result.description,
        source_file: entry.source_file,
        ui_element: llm_result.ui_element,
        tone: llm_result.tone,
        max_length: llm_result.max_length,
        locations: matches.map { |m| "#{m.file}:#{m.line}" },
        error: llm_result.error
      )

      cache.set(entry.key, entry.text, result.to_h.except(:source_file), context: cache_ctx)
      result
    end

    def write_output
      writer = case @config.output_format.to_s.downcase
               when 'json'
                 Writers::JsonWriter.new
               else
                 Writers::CsvWriter.new
               end

      writer.write(@results, @config.output_path)
    end

    def write_back_to_source
      @config.translations.each do |path|
        next unless File.exist?(path)

        writer = source_writer_for(path)
        next unless writer

        relevant_results = @results.select { |result| result_matches_source_path?(result, path) }
        next if relevant_results.empty?

        writer.write(relevant_results, path)
        puts "Updated #{path} with context comments"
      end
    end

    def write_back_to_code
      swift_writer = Writers::SwiftWriter.new(
        functions: @config.swift_functions,
        context_prefix: @config.context_prefix,
        context_mode: @config.context_mode
      )

      updated_count = 0
      results_by_key = build_results_by_key_for_code_write_back

      @config.source_paths.each do |source_path|
        swift_files = find_swift_files(source_path, ignore_patterns: @config.ignore_patterns)

        swift_files.each do |swift_file|
          if swift_writer.update_file(swift_file, results_by_key)
            updated_count += 1
            puts "Updated #{swift_file} with context comments"
          end
        end
      end

      puts "Updated #{updated_count} Swift files with context comments" if updated_count.positive?
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
      basename = File.basename(path).downcase
      ext = File.extname(path).downcase

      case ext
      when '.strings'
        Writers::StringsWriter.new(
          context_prefix: @config.context_prefix,
          context_mode: @config.context_mode
        )
      when '.xml'
        if basename == 'strings.xml' || path.include?('/res/values')
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
