# frozen_string_literal: true

require 'set' # rubocop:disable Lint/RedundantRequireStatement -- required when Config is loaded directly
require_relative 'config/schema'
require_relative 'config/validation'
require_relative 'config/serialization'
require_relative 'config/defaults'
require_relative 'config/cli_values'

module I18nContextGenerator
  # Holds all configuration for an extraction run, loaded from YAML config files and/or CLI options.
  class Config
    include Validation
    include Serialization
    extend Defaults
    extend CliValues

    attr_reader :translations, :source_paths, :source_line_filter, :ignore_patterns,
                :provider, :model, :concurrency, :context_lines,
                :max_matches_per_key, :output_path, :output_format,
                :no_cache, :dry_run, :key_filter, :write_back,
                :swift_functions, :write_back_to_code, :diff_base, :diff_head, :context_prefix,
                :context_mode, :start_key, :end_key, :include_file_paths,
                :include_translation_comments, :redact_prompts, :discovery_mode,
                :platform, :translation_locales, :max_prompt_chars, :cache_dir, :endpoint,
                :schema_version, :output_stdout, :print_config, :workflow_stage,
                :context_files, :supplemental_context

    DEFAULT_CONTEXT_PREFIX = Schema.default(:context_prefix).freeze
    DEFAULT_CONTEXT_MODE = Schema.default(:context_mode).freeze
    DEFAULT_MAX_PROMPT_CHARS = Schema.default(:max_prompt_chars)
    DEFAULT_CACHE_DIR = Schema.default(:cache_dir).freeze
    VALID_PROVIDERS = Schema.values(:provider)
    VALID_OUTPUT_FORMATS = Schema.values(:output_format)
    VALID_CONTEXT_MODES = Schema.values(:context_mode)
    VALID_DISCOVERY_MODES = Schema.values(:discovery_mode)
    VALID_PLATFORMS = Schema.values(:platform)
    VALID_OUTPUT_EXTENSIONS = { '.csv' => 'csv', '.json' => 'json' }.freeze

    def initialize(**attrs)
      @schema_version = fetch_defaulting_value(attrs, :schema_version, Schema.default(:schema_version))
      @translations = deduplicate_paths(fetch_defaulting_value(attrs, :translations, Schema.default(:translations)))
      @source_paths = deduplicate_source_paths(fetch_defaulting_value(attrs, :source_paths, Schema.default(:source_paths)))
      @context_files = deduplicate_paths(fetch_defaulting_value(attrs, :context_files, Schema.default(:context_files)))
      @supplemental_context = fetch_defaulting_value(attrs, :supplemental_context, {})
      @source_line_filter = fetch_config_value(attrs, :source_line_filter, nil)
      @translation_locales = fetch_defaulting_value(attrs, :translation_locales, {})
      @ignore_patterns = self.class.merge_ignore_patterns(fetch_defaulting_value(attrs, :ignore_patterns, Schema.default(:ignore_patterns)))
      @provider = normalize_enum_value(fetch_defaulting_value(attrs, :provider, Schema.default(:provider)))
      @model = fetch_config_value(attrs, :model, nil)
      @endpoint = fetch_config_value(attrs, :endpoint, nil)
      @concurrency = fetch_defaulting_value(attrs, :concurrency, Schema.default(:concurrency))
      @context_lines = fetch_defaulting_value(attrs, :context_lines, Schema.default(:context_lines))
      @max_matches_per_key = fetch_defaulting_value(attrs, :max_matches_per_key, Schema.default(:max_matches_per_key))
      @max_prompt_chars = fetch_defaulting_value(attrs, :max_prompt_chars, Schema.default(:max_prompt_chars))
      configured_output_path = fetch_config_value(attrs, :output_path, nil)
      explicit_stdout = fetch_boolean_value(attrs, :output_stdout, Schema.default(:output_stdout))
      @output_stdout = explicit_stdout || configured_output_path == '-'
      @output_destination_conflict = explicit_stdout && !configured_output_path.nil? && configured_output_path != '-'
      @output_path = @output_stdout ? '-' : configured_output_path
      @output_format_explicit = attrs.key?(:output_format) && !attrs[:output_format].nil?
      @output_format = normalize_enum_value(resolve_output_format(attrs[:output_format], @output_path))
      @no_cache = fetch_boolean_value(attrs, :no_cache, !Schema.default(:cache_enabled))
      @cache_dir = fetch_defaulting_value(attrs, :cache_dir, Schema.default(:cache_dir))
      @dry_run = fetch_boolean_value(attrs, :dry_run, Schema.default(:dry_run))
      @print_config = fetch_boolean_value(attrs, :print_config, Schema.default(:print_config))
      @workflow_stage = normalize_enum_value(
        fetch_defaulting_value(attrs, :workflow_stage, Schema.default(:workflow_stage))
      )
      @key_filter = fetch_config_value(attrs, :key_filter, nil)
      @write_back = fetch_boolean_value(attrs, :write_back, Schema.default(:write_back))
      @write_back_to_code = fetch_boolean_value(attrs, :write_back_to_code, Schema.default(:write_back_to_code))
      @swift_functions = merge_swift_functions(
        fetch_defaulting_value(attrs, :swift_functions, default_swift_functions)
      )
      @diff_base = fetch_config_value(attrs, :diff_base, nil)
      @diff_head = fetch_defaulting_value(attrs, :diff_head, Schema.default(:diff_head))
      @context_prefix = fetch_defaulting_value(attrs, :context_prefix, Schema.default(:context_prefix))
      @context_mode = normalize_enum_value(fetch_defaulting_value(attrs, :context_mode, Schema.default(:context_mode)))
      @start_key = fetch_config_value(attrs, :start_key, nil)
      @end_key = fetch_config_value(attrs, :end_key, nil)
      @include_file_paths = fetch_boolean_value(attrs, :include_file_paths, Schema.default(:include_file_paths))
      @include_translation_comments = fetch_boolean_value(attrs, :include_translation_comments, Schema.default(:include_translation_comments))
      @redact_prompts = fetch_boolean_value(attrs, :redact_prompts, Schema.default(:redact_prompts))
      @discovery_mode = normalize_enum_value(fetch_defaulting_value(attrs, :discovery_mode, Schema.default(:discovery_mode)))
      @platform = normalize_enum_value(fetch_config_value(attrs, :platform, nil))
    end

    def default_swift_functions
      Schema.default(:swift_functions)
    end

    def self.load(options)
      return from_cli(options) unless options[:config]

      raise Error, "Config file not found: #{options[:config]}" unless File.file?(options[:config])

      from_file(options[:config]).merge_cli(options)
    end

    def self.from_file(path)
      yaml = YAML.safe_load_file(path, permitted_classes: []) || {}
      raise Error, "Invalid config #{path}: root must be a mapping" unless yaml.is_a?(Hash)

      schema_version = Schema.validate_document!(yaml, path: path)
      %w[source context llm processing output swift privacy workflow].each { |section| config_section(yaml, section, path) }
      cache = config_section(yaml, 'cache', path)
      invalid_cache_enabled = cache.key?('enabled') && ![true, false].include?(cache['enabled'])
      raise Error, "Invalid config #{path}: cache.enabled must be true or false" if invalid_cache_enabled

      translation_settings = parse_translation_settings(yaml['translations'], path: path)

      attrs = {
        schema_version: schema_version,
        translations: translation_settings[:paths],
        translation_locales: translation_settings[:locales],
        source_paths: Schema.value(yaml, :source_paths),
        ignore_patterns: Schema.value(yaml, :ignore_patterns),
        context_files: Schema.value(yaml, :context_files),
        provider: Schema.value(yaml, :provider),
        model: Schema.value(yaml, :model),
        endpoint: Schema.value(yaml, :endpoint),
        concurrency: Schema.value(yaml, :concurrency),
        context_lines: Schema.value(yaml, :context_lines),
        max_matches_per_key: Schema.value(yaml, :max_matches_per_key),
        max_prompt_chars: Schema.value(yaml, :max_prompt_chars),
        discovery_mode: Schema.value(yaml, :discovery_mode),
        platform: Schema.value(yaml, :platform),
        output_path: Schema.value(yaml, :output_path),
        output_stdout: Schema.value(yaml, :output_stdout),
        write_back: Schema.value(yaml, :write_back),
        write_back_to_code: Schema.value(yaml, :write_back_to_code),
        swift_functions: Schema.value(yaml, :swift_functions),
        no_cache: !Schema.value(yaml, :cache_enabled),
        cache_dir: Schema.value(yaml, :cache_dir),
        workflow_stage: Schema.value(yaml, :workflow_stage)
      }
      attrs[:output_format] = Schema.value(yaml, :output_format) if Schema.configured?(yaml, :output_format)
      attrs[:context_mode] = Schema.value(yaml, :context_mode) if Schema.configured?(yaml, :context_mode)

      # Only pass context_prefix when explicitly set in YAML, so initialize default applies
      attrs[:context_prefix] = Schema.value(yaml, :context_prefix) if Schema.configured?(yaml, :context_prefix)
      attrs[:include_file_paths] = Schema.value(yaml, :include_file_paths) if Schema.configured?(yaml, :include_file_paths)
      attrs[:include_translation_comments] = Schema.value(yaml, :include_translation_comments) if Schema.configured?(yaml, :include_translation_comments)
      attrs[:redact_prompts] = Schema.value(yaml, :redact_prompts) if Schema.configured?(yaml, :redact_prompts)

      new(**attrs)
    rescue Psych::SyntaxError => e
      raise Error, "Invalid config YAML #{path}: #{e.problem} at line #{e.line}, column #{e.column}"
    rescue Psych::Exception => e
      raise Error, "Invalid config YAML #{path}: #{e.message}"
    rescue SystemCallError => e
      raise Error, "Unable to read config #{path}: #{e.message}"
    end

    def self.from_cli(options)
      translations = cli_path_list(options[:translation], legacy: options[:translations])
      source_paths = cli_path_list(options[:source])
      source_paths = Schema.default(:source_paths) if source_paths.empty?
      context_files = cli_path_list(options[:context_file])
      key_filters = cli_key_filters(options[:key], legacy: options[:keys])

      attrs = {
        schema_version: Schema::VERSION,
        translations: translations,
        source_paths: source_paths,
        context_files: context_files,
        ignore_patterns: [],
        provider: options[:provider] || Schema.default(:provider),
        model: options[:model],
        endpoint: options[:endpoint],
        concurrency: options[:concurrency] || Schema.default(:concurrency),
        context_lines: Schema.default(:context_lines),
        max_matches_per_key: Schema.default(:max_matches_per_key),
        discovery_mode: options[:discovery_mode] || Schema.default(:discovery_mode),
        platform: options[:platform],
        output_path: options[:output],
        output_stdout: options[:stdout],
        dry_run: options[:dry_run] || Schema.default(:dry_run),
        print_config: options[:print_config],
        workflow_stage: options[:workflow_stage] || Schema.default(:workflow_stage),
        key_filter: key_filters.empty? ? nil : key_filters,
        write_back: options[:write_back] || Schema.default(:write_back),
        write_back_to_code: options[:write_back_to_code] || Schema.default(:write_back_to_code),
        diff_base: options[:diff_base],
        diff_head: options[:diff_head],
        start_key: options[:start_key],
        end_key: options[:end_key]
      }
      attrs.merge!(cache_cli_attributes(options))
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
      translations = self.class.cli_path_list(options[:translation], legacy: options[:translations])
      if translations.any?
        @translations = deduplicate_paths(translations)
        @translation_locales = {}
      end
      source_paths = self.class.cli_path_list(options[:source])
      @source_paths = deduplicate_source_paths(source_paths) if source_paths.any?
      context_files = self.class.cli_path_list(options[:context_file])
      @context_files = deduplicate_paths(context_files) if context_files.any?
      key_filters = self.class.cli_key_filters(options[:key], legacy: options[:keys])
      @key_filter = key_filters if key_filters.any?
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
          unknown_keys = translation.keys - %w[path locale]
          raise Error, "Invalid translation entry: unknown keys: #{unknown_keys.join(', ')}" if unknown_keys.any?

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

    def self.cache_cli_attributes(options)
      {
        no_cache: options[:cache].nil? ? !Schema.default(:cache_enabled) : !options[:cache],
        cache_dir: options[:cache_dir] || Schema.default(:cache_dir),
        max_prompt_chars: options[:max_prompt_chars] || Schema.default(:max_prompt_chars)
      }
    end

    private_class_method :valid_nonempty_string?, :conflicting_locale?, :config_section,
                         :cache_cli_attributes

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

    def merge_swift_functions(functions)
      return functions unless functions.is_a?(Array) && functions.all?(String)

      LocalizationSyntax.functions_with_defaults(functions)
    end

    def merge_cli_scalar_options(options)
      scalar_mappings = {
        concurrency: :concurrency,
        max_prompt_chars: :max_prompt_chars,
        cache_dir: :cache_dir,
        endpoint: :endpoint,
        workflow_stage: :workflow_stage,
        discovery_mode: :discovery_mode,
        platform: :platform,
        diff_base: :diff_base,
        diff_head: :diff_head,
        context_prefix: :context_prefix,
        context_mode: :context_mode,
        start_key: :start_key,
        end_key: :end_key
      }

      scalar_mappings.each do |attr_name, option_name|
        value = options[option_name]
        value = normalize_enum_value(value) if %i[discovery_mode platform context_mode workflow_stage].include?(attr_name)
        instance_variable_set(:"@#{attr_name}", value) unless value.nil?
      end
    end

    def merge_cli_provider_and_model(options)
      provider = normalize_enum_value(options[:provider])
      if provider && provider != @provider
        @provider = provider
        @model = nil unless options[:model]
        @endpoint = nil unless options[:endpoint]
      end
      @model = options[:model] if options[:model]
    end

    def merge_cli_output(options)
      if options[:output]
        output_is_stdout = options[:output] == '-'
        @output_destination_conflict = options[:stdout] == true && !output_is_stdout
        @output_path = options[:output]
        @output_stdout = output_is_stdout
      elsif !options[:stdout].nil?
        @output_stdout = options[:stdout]
        @output_path = options[:stdout] ? '-' : nil
        @output_destination_conflict = false
      end
      if options[:format]
        @output_format = normalize_enum_value(options[:format])
        @output_format_explicit = true
      elsif options[:output] && !@output_format_explicit
        @output_format = resolve_output_format(nil, @output_path)
      end
    end

    def merge_cli_boolean_options(options)
      boolean_mappings = {
        dry_run: :dry_run,
        print_config: :print_config,
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

    def normalize_enum_value(value)
      value&.to_s
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
