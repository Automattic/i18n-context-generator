# frozen_string_literal: true

require_relative 'config/validation'

module I18nContextGenerator
  # Holds all configuration for an extraction run, loaded from YAML config files and/or CLI options.
  class Config
    include Validation

    attr_reader :translations, :source_paths, :source_line_filter, :ignore_patterns,
                :provider, :model, :concurrency, :context_lines,
                :max_matches_per_key, :output_path, :output_format,
                :no_cache, :dry_run, :key_filter, :write_back,
                :swift_functions, :write_back_to_code, :diff_base, :context_prefix,
                :context_mode, :start_key, :end_key, :include_file_paths,
                :include_translation_comments, :redact_prompts, :discovery_mode,
                :platform, :translation_locales

    DEFAULT_CONTEXT_PREFIX = 'Context: '
    DEFAULT_CONTEXT_MODE = 'replace' # "replace" or "append"
    VALID_PROVIDERS = %w[anthropic openai].freeze
    VALID_OUTPUT_FORMATS = %w[csv json].freeze
    VALID_CONTEXT_MODES = %w[replace append].freeze
    VALID_DISCOVERY_MODES = %w[auto translations source].freeze
    VALID_PLATFORMS = %w[ios android].freeze
    VALID_OUTPUT_EXTENSIONS = { '.csv' => 'csv', '.json' => 'json' }.freeze

    def initialize(**attrs)
      @translations = deduplicate_paths(fetch_defaulting_value(attrs, :translations, []))
      @source_paths = deduplicate_source_paths(fetch_defaulting_value(attrs, :source_paths, ['.']))
      @source_line_filter = fetch_config_value(attrs, :source_line_filter, nil)
      @translation_locales = fetch_defaulting_value(attrs, :translation_locales, {})
      @ignore_patterns = self.class.merge_ignore_patterns(fetch_defaulting_value(attrs, :ignore_patterns, []))
      @provider = fetch_defaulting_value(attrs, :provider, 'anthropic')
      @model = fetch_config_value(attrs, :model, nil)
      @concurrency = fetch_defaulting_value(attrs, :concurrency, 5)
      @context_lines = fetch_defaulting_value(attrs, :context_lines, 15)
      @max_matches_per_key = fetch_defaulting_value(attrs, :max_matches_per_key, 3)
      @output_path = fetch_config_value(attrs, :output_path, nil)
      @output_format_explicit = attrs.key?(:output_format) && !attrs[:output_format].nil?
      @output_format = resolve_output_format(attrs[:output_format], @output_path)
      @no_cache = fetch_boolean_value(attrs, :no_cache, true)
      @dry_run = fetch_boolean_value(attrs, :dry_run, false)
      @key_filter = fetch_config_value(attrs, :key_filter, nil)
      @write_back = fetch_boolean_value(attrs, :write_back, false)
      @write_back_to_code = fetch_boolean_value(attrs, :write_back_to_code, false)
      @swift_functions = fetch_defaulting_value(attrs, :swift_functions, default_swift_functions)
      @diff_base = fetch_config_value(attrs, :diff_base, nil)
      @context_prefix = fetch_defaulting_value(attrs, :context_prefix, DEFAULT_CONTEXT_PREFIX)
      @context_mode = fetch_defaulting_value(attrs, :context_mode, DEFAULT_CONTEXT_MODE)
      @start_key = fetch_config_value(attrs, :start_key, nil)
      @end_key = fetch_config_value(attrs, :end_key, nil)
      @include_file_paths = fetch_boolean_value(attrs, :include_file_paths, false)
      @include_translation_comments = fetch_boolean_value(attrs, :include_translation_comments, true)
      @redact_prompts = fetch_boolean_value(attrs, :redact_prompts, true)
      @discovery_mode = fetch_defaulting_value(attrs, :discovery_mode, 'auto')
      @platform = fetch_config_value(attrs, :platform, nil)
    end

    def default_swift_functions
      %w[NSLocalizedString String(localized: Text(]
    end

    def self.load(options)
      return from_cli(options) unless options[:config]

      raise Error, "Config file not found: #{options[:config]}" unless File.file?(options[:config])

      from_file(options[:config]).merge_cli(options)
    end

    def self.from_file(path)
      yaml = YAML.safe_load_file(path, permitted_classes: []) || {}
      raise Error, "Invalid config #{path}: root must be a mapping" unless yaml.is_a?(Hash)

      source = config_section(yaml, 'source', path)
      llm = config_section(yaml, 'llm', path)
      processing = config_section(yaml, 'processing', path)
      output = config_section(yaml, 'output', path)
      swift = config_section(yaml, 'swift', path)
      privacy = config_section(yaml, 'privacy', path)
      translation_settings = parse_translation_settings(yaml['translations'], path: path)

      attrs = {
        translations: translation_settings[:paths],
        translation_locales: translation_settings[:locales],
        source_paths: source.fetch('paths', ['.']),
        ignore_patterns: source.fetch('ignore', []),
        provider: llm.fetch('provider', 'anthropic'),
        model: llm['model'],
        concurrency: processing.fetch('concurrency', 5),
        context_lines: processing.fetch('context_lines', 15),
        max_matches_per_key: processing.fetch('max_matches_per_key', 3),
        discovery_mode: processing.fetch('discovery_mode', 'auto'),
        platform: processing['platform'],
        output_path: output['path'],
        write_back: output.fetch('write_back', false),
        write_back_to_code: output.fetch('write_back_to_code', false),
        swift_functions: swift.fetch('functions', nil)
      }
      attrs[:output_format] = output['format'] if output.key?('format')
      attrs[:context_mode] = output['context_mode'] if output.key?('context_mode')

      # Only pass context_prefix when explicitly set in YAML, so initialize default applies
      prefix = output['context_prefix']
      attrs[:context_prefix] = prefix unless prefix.nil?
      attrs[:include_file_paths] = privacy['include_file_paths'] if privacy.key?('include_file_paths')
      attrs[:include_translation_comments] = privacy['include_translation_comments'] if privacy.key?('include_translation_comments')
      attrs[:redact_prompts] = privacy['redact_prompts'] if privacy.key?('redact_prompts')

      new(**attrs)
    rescue Psych::SyntaxError => e
      raise Error, "Invalid config YAML #{path}: #{e.problem} at line #{e.line}, column #{e.column}"
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
        ignore_patterns: [],
        provider: options[:provider] || 'anthropic',
        model: options[:model],
        concurrency: options[:concurrency] || 5,
        context_lines: 15,
        max_matches_per_key: 3,
        discovery_mode: options[:discovery_mode] || 'auto',
        platform: options[:platform],
        output_path: options[:output],
        no_cache: options[:cache].nil? || !options[:cache],
        dry_run: options[:dry_run] || false,
        key_filter: options[:keys],
        write_back: options[:write_back] || false,
        write_back_to_code: options[:write_back_to_code] || false,
        diff_base: options[:diff_base],
        start_key: options[:start_key],
        end_key: options[:end_key]
      }
      attrs[:output_format] = options[:format] if options[:format]

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
      if options[:translations]
        @translations = deduplicate_paths(options[:translations].split(',').map(&:strip))
        @translation_locales = {}
      end
      @source_paths = deduplicate_source_paths(options[:source].split(',').map(&:strip)) if options[:source]
      merge_cli_provider_and_model(options)
      merge_cli_output(options)
      merge_cli_scalar_options(options)
      merge_cli_boolean_options(options)
      self
    end

    def self.parse_translations(translations)
      parse_translation_settings(translations)[:paths]
    end

    def self.parse_translation_settings(translations, path: nil)
      return { paths: [], locales: {} } if translations.nil?

      unless translations.is_a?(Array)
        location = path ? " in #{path}" : ''
        raise Error, "Invalid translations#{location}: expected an array"
      end

      paths = []
      locales = {}

      translations.each do |translation|
        case translation
        when String
          paths << translation
        when Hash
          translation_path = translation['path']
          raise Error, 'Invalid translation entry: path must be a non-empty string' unless valid_nonempty_string?(translation_path)

          locale = translation['locale']
          raise Error, "Invalid translation locale for #{translation_path}: expected a non-empty string" unless locale.nil? || valid_nonempty_string?(locale)
          raise Error, "Conflicting translation locales for #{translation_path}" if conflicting_locale?(locales, translation_path, locale)

          paths << translation_path
          locales[translation_path] = locale if locale
        else
          raise Error, 'Invalid translation entry: expected a path string or mapping'
        end
      end

      { paths: paths.uniq, locales: locales }
    end

    def self.valid_nonempty_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def self.conflicting_locale?(locales, path, locale)
      locale && locales.key?(path) && locales[path] != locale
    end

    def self.config_section(yaml, name, path)
      value = yaml[name]
      return {} if value.nil?

      raise Error, "Invalid config #{path}: #{name} must be a mapping" unless value.is_a?(Hash)

      value
    end

    private_class_method :valid_nonempty_string?, :conflicting_locale?, :config_section

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

    def self.merge_ignore_patterns(patterns)
      return patterns unless patterns.is_a?(Array)

      (default_ignore_patterns + patterns).compact.uniq
    end

    private

    def fetch_config_value(attrs, key, default)
      attrs.key?(key) ? attrs[key] : default
    end

    def fetch_defaulting_value(attrs, key, default)
      attrs.key?(key) ? (attrs[key] || default) : default
    end

    def fetch_boolean_value(attrs, key, default)
      return default unless attrs.key?(key)

      attrs[key].nil? ? default : attrs[key]
    end

    def merge_cli_scalar_options(options)
      scalar_mappings = {
        key_filter: :keys,
        concurrency: :concurrency,
        discovery_mode: :discovery_mode,
        platform: :platform,
        diff_base: :diff_base,
        context_prefix: :context_prefix,
        context_mode: :context_mode,
        start_key: :start_key,
        end_key: :end_key
      }

      scalar_mappings.each do |attr_name, option_name|
        value = options[option_name]
        instance_variable_set(:"@#{attr_name}", value) unless value.nil?
      end
    end

    def merge_cli_provider_and_model(options)
      if options[:provider] && options[:provider] != @provider
        @provider = options[:provider]
        @model = nil unless options[:model]
      end
      @model = options[:model] if options[:model]
    end

    def merge_cli_output(options)
      @output_path = options[:output] if options[:output]
      if options[:format]
        @output_format = options[:format]
        @output_format_explicit = true
      elsif options[:output] && !@output_format_explicit
        @output_format = resolve_output_format(nil, @output_path)
      end
    end

    def merge_cli_boolean_options(options)
      boolean_mappings = {
        dry_run: :dry_run,
        write_back: :write_back,
        write_back_to_code: :write_back_to_code,
        include_file_paths: :include_file_paths,
        include_translation_comments: :include_translation_comments,
        redact_prompts: :redact_prompts
      }

      @no_cache = !options[:cache] unless options[:cache].nil?
      boolean_mappings.each do |attr_name, option_name|
        value = options[option_name]
        instance_variable_set(:"@#{attr_name}", value) unless value.nil?
      end
    end

    def resolve_output_format(configured_format, output_path)
      return configured_format unless configured_format.nil?

      VALID_OUTPUT_EXTENSIONS.fetch(File.extname(output_path.to_s).downcase, 'csv')
    end

    def deduplicate_paths(paths)
      paths.is_a?(Array) ? paths.uniq : paths
    end

    def deduplicate_source_paths(paths)
      return paths unless paths.is_a?(Array) && paths.all?(String)

      seen_expanded_paths = Set.new
      unique_paths = paths.select { |path| seen_expanded_paths.add?(File.expand_path(path)) }
      unique_paths.reject do |path|
        expanded = File.expand_path(path)
        unique_paths.any? do |other|
          next false if other == path

          expanded.start_with?(directory_prefix(other))
        end
      end
    end

    def directory_prefix(path)
      expanded = File.expand_path(path)
      expanded.end_with?(File::SEPARATOR) ? expanded : "#{expanded}#{File::SEPARATOR}"
    end
  end
end
