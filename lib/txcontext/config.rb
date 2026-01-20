# frozen_string_literal: true

module Txcontext
  class Config
    attr_reader :translations, :source_paths, :ignore_patterns,
                :provider, :model, :concurrency, :context_lines,
                :max_matches_per_key, :output_path, :output_format,
                :no_cache, :dry_run, :key_filter, :custom_prompt, :write_back,
                :swift_functions, :write_back_to_code, :diff_base, :context_prefix,
                :context_mode

    DEFAULT_CONTEXT_PREFIX = "Context: "
    DEFAULT_CONTEXT_MODE = "replace" # "replace" or "append"

    def initialize(**attrs)
      @translations = attrs[:translations] || []
      @source_paths = attrs[:source_paths] || ["."]
      @ignore_patterns = attrs[:ignore_patterns] || []
      @provider = attrs[:provider] || "anthropic"
      @model = attrs[:model]
      @concurrency = attrs[:concurrency] || 5
      @context_lines = attrs[:context_lines] || 20
      @max_matches_per_key = attrs[:max_matches_per_key] || 3
      @output_path = attrs[:output_path] || "translation-context.csv"
      @output_format = attrs[:output_format] || "csv"
      @no_cache = attrs[:no_cache] || false
      @dry_run = attrs[:dry_run] || false
      @key_filter = attrs[:key_filter]
      @custom_prompt = attrs[:custom_prompt]
      @write_back = attrs[:write_back] || false
      @write_back_to_code = attrs[:write_back_to_code] || false
      @swift_functions = attrs[:swift_functions] || default_swift_functions
      @diff_base = attrs[:diff_base]
      @context_prefix = attrs.key?(:context_prefix) ? attrs[:context_prefix] : DEFAULT_CONTEXT_PREFIX
      @context_mode = attrs[:context_mode] || DEFAULT_CONTEXT_MODE
    end

    def default_swift_functions
      %w[NSLocalizedString String(localized: Text(]
    end

    def self.load(options)
      if options[:config] && File.exist?(options[:config])
        from_file(options[:config]).merge_cli(options)
      else
        from_cli(options)
      end
    end

    def self.from_file(path)
      yaml = YAML.load_file(path)

      new(
        translations: parse_translations(yaml["translations"]),
        source_paths: yaml.dig("source", "paths") || ["."],
        ignore_patterns: yaml.dig("source", "ignore") || default_ignore_patterns,
        provider: yaml.dig("llm", "provider") || "anthropic",
        model: yaml.dig("llm", "model"),
        concurrency: yaml.dig("processing", "concurrency") || 5,
        context_lines: yaml.dig("processing", "context_lines") || 20,
        max_matches_per_key: yaml.dig("processing", "max_matches_per_key") || 3,
        output_path: yaml.dig("output", "path") || "translation-context.csv",
        output_format: yaml.dig("output", "format") || "csv",
        write_back: yaml.dig("output", "write_back") || false,
        write_back_to_code: yaml.dig("output", "write_back_to_code") || false,
        context_prefix: yaml.dig("output", "context_prefix"),
        context_mode: yaml.dig("output", "context_mode"),
        swift_functions: yaml.dig("swift", "functions"),
        custom_prompt: yaml["prompt"]
      )
    end

    def self.from_cli(options)
      translations = if options[:translations]
                       options[:translations].split(",").map(&:strip)
                     else
                       []
                     end

      source_paths = if options[:source]
                       options[:source].split(",").map(&:strip)
                     else
                       ["."]
                     end

      new(
        translations: translations,
        source_paths: source_paths,
        ignore_patterns: default_ignore_patterns,
        provider: options[:provider] || "anthropic",
        model: options[:model],
        concurrency: options[:concurrency] || 5,
        context_lines: 20,
        max_matches_per_key: 3,
        output_path: options[:output] || "translation-context.csv",
        output_format: options[:format] || "csv",
        no_cache: options[:no_cache] || false,
        dry_run: options[:dry_run] || false,
        key_filter: options[:keys],
        write_back: options[:write_back] || false,
        write_back_to_code: options[:write_back_to_code] || false,
        diff_base: options[:diff_base],
        context_prefix: options[:context_prefix],
        context_mode: options[:context_mode]
      )
    end

    def merge_cli(options)
      @no_cache = options[:no_cache] if options[:no_cache]
      @dry_run = options[:dry_run] if options[:dry_run]
      @key_filter = options[:keys] if options[:keys]
      @output_path = options[:output] if options[:output]
      @provider = options[:provider] if options[:provider]
      @model = options[:model] if options[:model]
      @concurrency = options[:concurrency] if options[:concurrency]
      @write_back = options[:write_back] if options[:write_back]
      @write_back_to_code = options[:write_back_to_code] if options[:write_back_to_code]
      @diff_base = options[:diff_base] if options[:diff_base]
      @context_prefix = options[:context_prefix] if options.key?(:context_prefix)
      @context_mode = options[:context_mode] if options[:context_mode]
      self
    end

    def self.parse_translations(translations)
      return [] unless translations

      translations.map do |t|
        t.is_a?(Hash) ? t["path"] : t
      end
    end

    def self.default_ignore_patterns
      [
        "**/node_modules/**",
        "**/vendor/**",
        "**/.git/**",
        "**/build/**",
        "**/dist/**",
        "**/*.min.js",
        "**/*.test.*",
        "**/*.spec.*"
      ]
    end
  end
end
