# frozen_string_literal: true

module Txcontext
  class ContextExtractor
    # Result for a single translation key
    ExtractionResult = Data.define(:key, :text, :description, :ui_element, :tone,
                                   :max_length, :locations, :error) do
      def initialize(key:, text:, description:, ui_element: nil, tone: nil,
                     max_length: nil, locations: [], error: nil)
        super
      end

      def to_h
        {
          key: key,
          text: text,
          description: description,
          ui_element: ui_element,
          tone: tone,
          max_length: max_length,
          locations: locations,
          error: error
        }
      end
    end

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
      entries = load_translations
      entries = filter_entries(entries) if @config.key_filter
      entries = filter_by_diff(entries) if @config.diff_base

      if entries.empty?
        if @config.diff_base
          puts "No changed translation keys found since #{@config.diff_base}."
        else
          puts "No translation entries found."
        end
        return
      end

      puts "Loaded #{entries.size} translation keys"
      puts "(filtered to changes since #{@config.diff_base})" if @config.diff_base

      if @config.dry_run
        puts "\nDry run - would process these keys:"
        entries.first(20).each { |e| puts "  - #{e.key}: #{e.text.truncate(50)}" }
        puts "  ... and #{entries.size - 20} more" if entries.size > 20
        return
      end

      process_entries(entries)
      write_output

      if @config.write_back
        write_back_to_source
      end

      if @config.write_back_to_code
        write_back_to_code
      end

      puts "\nWrote #{@results.size} results to #{@config.output_path}"
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
      @config.translations.flat_map do |path|
        unless File.exist?(path)
          warn "Translation file not found: #{path}"
          next []
        end

        parser = Parsers::Base.for(path)
        parser.parse(path)
      end
    end

    def filter_entries(entries)
      patterns = @config.key_filter.split(",").map do |pattern|
        Regexp.new("^#{pattern.strip.gsub('*', '.*')}$")
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

      entries.select { |entry| changed_keys.include?(entry.key) }
    end

    def process_entries(entries)
      progress = TTY::ProgressBar.new(
        "[:bar] :current/:total :percent :eta",
        total: entries.size,
        width: 40
      )

      # Use a thread pool for concurrent processing
      pool = Concurrent::FixedThreadPool.new(@config.concurrency)
      semaphore = Concurrent::Semaphore.new(@config.concurrency)

      entries.each do |entry|
        pool.post do
          semaphore.acquire
          begin
            result = process_entry(entry)
            @results << result
            @errors << result if result.error
          rescue StandardError => e
            # Capture errors as results so they're visible in output
            result = ExtractionResult.new(
              key: entry.key,
              text: entry.text,
              description: "Processing failed",
              error: e.message
            )
            @results << result
            @errors << result
          ensure
            semaphore.release
            progress.advance
          end
        end
      end

      pool.shutdown
      pool.wait_for_termination
    end

    def process_entry(entry)
      # Check cache first
      if (cached = cache.get(entry.key, entry.text))
        return ExtractionResult.new(**cached.transform_keys(&:to_sym))
      end

      # Search for key usage in code
      matches = searcher.search(entry.key)

      if matches.empty?
        result = ExtractionResult.new(
          key: entry.key,
          text: entry.text,
          description: "No usage found in source code",
          locations: []
        )
        cache.set(entry.key, entry.text, result.to_h)
        return result
      end

      # Limit matches to avoid huge prompts
      matches = matches.first(@config.max_matches_per_key)

      # Get context from LLM
      llm_result = llm.generate_context(
        key: entry.key,
        text: entry.text,
        matches: matches,
        model: @config.model
      )

      result = ExtractionResult.new(
        key: entry.key,
        text: entry.text,
        description: llm_result.description,
        ui_element: llm_result.ui_element,
        tone: llm_result.tone,
        max_length: llm_result.max_length,
        locations: matches.map { |m| "#{m.file}:#{m.line}" },
        error: llm_result.error
      )

      cache.set(entry.key, entry.text, result.to_h)
      result
    end

    def write_output
      writer = case @config.output_format.to_s.downcase
               when "json"
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

        writer.write(@results, path)
        puts "Updated #{path} with context comments"
      end
    end

    def write_back_to_code
      swift_writer = Writers::SwiftWriter.new(functions: @config.swift_functions)

      updated_count = 0
      results_by_key = @results.to_h { |r| [r.key, r] }

      @config.source_paths.each do |source_path|
        swift_files = find_swift_files(source_path)

        swift_files.each do |swift_file|
          if swift_writer.update_file(swift_file, results_by_key)
            updated_count += 1
            puts "Updated #{swift_file} with context comments"
          end
        end
      end

      puts "Updated #{updated_count} Swift files with context comments" if updated_count > 0
    end

    def find_swift_files(path)
      if File.file?(path) && path.end_with?(".swift")
        [path]
      elsif File.directory?(path)
        Dir.glob(File.join(path, "**", "*.swift"))
      else
        []
      end
    end

    def source_writer_for(path)
      basename = File.basename(path).downcase
      ext = File.extname(path).downcase

      case ext
      when ".strings"
        Writers::StringsWriter.new
      when ".xml"
        Writers::AndroidXmlWriter.new if basename == "strings.xml" || path.include?("/res/values")
      else
        nil # No write-back support for other formats
      end
    end
  end
end

# Add truncate method if not available
unless String.method_defined?(:truncate)
  class String
    def truncate(length, omission: "...")
      return self if self.length <= length

      "#{self[0, length - omission.length]}#{omission}"
    end
  end
end
