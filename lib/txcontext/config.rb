# frozen_string_literal: true

module Txcontext
  # Holds all configuration for an extraction run, loaded from YAML config files and/or CLI options.
  class Config
    attr_reader :translations, :source_paths, :ignore_patterns,
                :provider, :model, :concurrency, :context_lines,
                :max_matches_per_key, :output_path, :output_format,
                :no_cache, :dry_run, :key_filter, :write_back,
                :swift_functions, :write_back_to_code, :diff_base, :context_prefix,
                :context_mode, :start_key, :end_key, :include_file_paths,
                :include_translation_comments, :redact_prompts

    DEFAULT_CONTEXT_PREFIX = 'Context: '
    DEFAULT_CONTEXT_MODE = 'replace' # "replace" or "append"

    def initialize(**attrs)
      @translations = attrs[:translations] || []
      @source_paths = attrs[:source_paths] || ['.']
      @ignore_patterns = attrs[:ignore_patterns] || []
      @provider = attrs[:provider] || 'anthropic'
      @model = attrs[:model]
      @concurrency = attrs[:concurrency] || 5
      @context_lines = attrs[:context_lines] || 15
      @max_matches_per_key = attrs[:max_matches_per_key] || 3
      @output_path = attrs.key?(:output_path) ? attrs[:output_path] : nil
      @output_format = attrs[:output_format] || 'csv'
      @no_cache = attrs.key?(:no_cache) ? attrs[:no_cache] : true
      @dry_run = attrs[:dry_run] || false
      @key_filter = attrs[:key_filter]
      @write_back = attrs[:write_back] || false
      @write_back_to_code = attrs[:write_back_to_code] || false
      @swift_functions = attrs[:swift_functions] || default_swift_functions
      @diff_base = attrs[:diff_base]
      @context_prefix = attrs.key?(:context_prefix) ? attrs[:context_prefix] : DEFAULT_CONTEXT_PREFIX
      @context_mode = attrs[:context_mode] || DEFAULT_CONTEXT_MODE
      @start_key = attrs[:start_key]
      @end_key = attrs[:end_key]
      @include_file_paths = attrs.key?(:include_file_paths) ? attrs[:include_file_paths] : false
      @include_translation_comments = attrs.key?(:include_translation_comments) ? attrs[:include_translation_comments] : true
      @redact_prompts = attrs.key?(:redact_prompts) ? attrs[:redact_prompts] : true
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
      yaml = YAML.safe_load_file(path, permitted_classes: []) || {}

      attrs = {
        translations: parse_translations(yaml['translations']),
        source_paths: yaml.dig('source', 'paths') || ['.'],
        ignore_patterns: yaml.dig('source', 'ignore') || default_ignore_patterns,
        provider: yaml.dig('llm', 'provider') || 'anthropic',
        model: yaml.dig('llm', 'model'),
        concurrency: yaml.dig('processing', 'concurrency') || 5,
        context_lines: yaml.dig('processing', 'context_lines') || 15,
        max_matches_per_key: yaml.dig('processing', 'max_matches_per_key') || 3,
        output_path: yaml.dig('output', 'path'),
        output_format: yaml.dig('output', 'format') || 'csv',
        write_back: yaml.dig('output', 'write_back') || false,
        write_back_to_code: yaml.dig('output', 'write_back_to_code') || false,
        context_mode: yaml.dig('output', 'context_mode'),
        swift_functions: yaml.dig('swift', 'functions')
      }

      # Only pass context_prefix when explicitly set in YAML, so initialize default applies
      prefix = yaml.dig('output', 'context_prefix')
      attrs[:context_prefix] = prefix unless prefix.nil?
      attrs[:include_file_paths] = yaml.dig('privacy', 'include_file_paths') unless yaml.dig('privacy', 'include_file_paths').nil?
      attrs[:include_translation_comments] = yaml.dig('privacy', 'include_translation_comments') unless yaml.dig('privacy', 'include_translation_comments').nil?
      attrs[:redact_prompts] = yaml.dig('privacy', 'redact_prompts') unless yaml.dig('privacy', 'redact_prompts').nil?

      new(**attrs)
    end

    def self.from_cli(options)
      translations = if options[:translations]
                       options[:translations].split(',').map(&:strip)
                     else
                       []
                     end

      source_paths = if options[:source]
                       options[:source].split(',').map(&:strip)
                     else
                       ['.']
                     end

      attrs = {
        translations: translations,
        source_paths: source_paths,
        ignore_patterns: default_ignore_patterns,
        provider: options[:provider] || 'anthropic',
        model: options[:model],
        concurrency: options[:concurrency] || 5,
        context_lines: 15,
        max_matches_per_key: 3,
        output_path: options[:output],
        output_format: options[:format] || 'csv',
        no_cache: options[:cache].nil? || !options[:cache],
        dry_run: options[:dry_run] || false,
        key_filter: options[:keys],
        write_back: options[:write_back] || false,
        write_back_to_code: options[:write_back_to_code] || false,
        diff_base: options[:diff_base],
        start_key: options[:start_key],
        end_key: options[:end_key]
      }

      # Only include if explicitly provided, so Config.new can apply its defaults
      attrs[:context_prefix] = options[:context_prefix] unless options[:context_prefix].nil?
      attrs[:context_mode] = options[:context_mode] if options[:context_mode]
      attrs[:include_file_paths] = options[:include_file_paths] unless options[:include_file_paths].nil?
      attrs[:include_translation_comments] = options[:include_translation_comments] unless options[:include_translation_comments].nil?
      attrs[:redact_prompts] = options[:redact_prompts] unless options[:redact_prompts].nil?

      new(**attrs)
    end

    # Merge CLI options over config-file values.
    # Only options explicitly passed by the user (non-nil) are merged.
    # Thor options without defaults are nil when not passed, so this
    # correctly preserves config-file values for unspecified flags.
    def merge_cli(options)
      @translations = options[:translations].split(',').map(&:strip) if options[:translations]
      @source_paths = options[:source].split(',').map(&:strip) if options[:source]
      merge_cli_scalar_options(options)
      merge_cli_boolean_options(options)
      self
    end

    def self.parse_translations(translations)
      return [] unless translations

      translations.map do |t|
        t.is_a?(Hash) ? t['path'] : t
      end
    end

    def self.default_ignore_patterns
      [
        '**/node_modules/**',
        '**/vendor/**',
        '**/.git/**',
        '**/build/**',
        '**/dist/**',
        '**/*.min.js',
        '**/*.test.*',
        '**/*.spec.*',
        '**/Pods/**',
        '**/Carthage/**',
        '**/.build/**',
        '**/DerivedData/**',
        '**/*Tests.swift',
        '**/*Tests.kt',
        '**/*Test.java',
        '**/*Test.kt'
      ]
    end

    private

    def merge_cli_scalar_options(options)
      scalar_mappings = {
        key_filter: :keys,
        output_path: :output,
        output_format: :format,
        provider: :provider,
        model: :model,
        concurrency: :concurrency,
        diff_base: :diff_base,
        context_prefix: :context_prefix,
        context_mode: :context_mode,
        start_key: :start_key,
        end_key: :end_key,
        include_file_paths: :include_file_paths,
        include_translation_comments: :include_translation_comments,
        redact_prompts: :redact_prompts
      }

      scalar_mappings.each do |attr_name, option_name|
        value = options[option_name]
        instance_variable_set(:"@#{attr_name}", value) unless value.nil?
      end
    end

    def merge_cli_boolean_options(options)
      boolean_mappings = {
        dry_run: :dry_run,
        write_back: :write_back,
        write_back_to_code: :write_back_to_code
      }

      @no_cache = !options[:cache] unless options[:cache].nil?
      boolean_mappings.each do |attr_name, option_name|
        value = options[option_name]
        instance_variable_set(:"@#{attr_name}", value) unless value.nil?
      end
    end
  end
end
