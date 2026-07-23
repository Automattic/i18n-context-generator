# frozen_string_literal: true

require_relative '../localization_syntax'

module I18nContextGenerator
  class Config
    # Typed registry for client-facing configuration. CLI metadata and sample
    # configuration defaults are derived from these definitions.
    module Schema
      VERSION = 1
      DOCUMENT_KEYS = %w[
        schema_version translations source context llm processing cache output swift privacy workflow
      ].freeze
      SECTION_KEYS = {
        'source' => %w[paths ignore],
        'context' => %w[files],
        'llm' => %w[provider model endpoint],
        'processing' => %w[
          concurrency context_lines max_matches_per_key max_prompt_chars discovery_mode platform
        ],
        'cache' => %w[enabled directory],
        'output' => %w[path format stdout write_back write_back_to_code context_prefix context_mode],
        'swift' => %w[functions],
        'privacy' => %w[include_file_paths include_translation_comments redact_prompts],
        'workflow' => %w[stage]
      }.freeze

      Definition = Data.define(:name, :type, :default, :values, :yaml_path, :cli) do
        def initialize(name:, type:, default:, values:, yaml_path:, cli:)
          default.freeze if default.respond_to?(:freeze)
          super(
            name: name,
            type: type,
            default: default,
            values: values&.freeze,
            yaml_path: yaml_path&.freeze,
            cli: cli&.freeze
          )
        end

        def cli?
          !cli.nil?
        end

        def cli_name
          cli.fetch(:name, name)
        end

        def thor_options
          options = { desc: help_description }
          options[:aliases] = cli[:aliases] if cli[:aliases]
          options[:type] = cli.fetch(:type) { Schema.thor_type(type) }
          options[:enum] = values if values
          options[:repeatable] = true if cli[:repeatable]
          options
        end

        private

        def help_description
          return cli[:description] unless cli[:show_default]

          label = cli[:default_note]&.then { |note| format(note, default) }
          label ||= cli[:quote_default] ? default.inspect : default.to_s
          "#{cli[:description]} (default: #{label})"
        end
      end

      DEFINITIONS = [
        Definition.new(name: :config, type: :string, default: nil, values: nil, yaml_path: nil,
                       cli: { aliases: '-c', description: 'Path to config file (.i18n-context-generator.yml)' }),
        Definition.new(name: :schema_version, type: :integer, default: VERSION, values: [VERSION],
                       yaml_path: ['schema_version'], cli: nil),
        Definition.new(name: :translations, type: :array, default: [], values: nil, yaml_path: ['translations'],
                       cli: { name: :translation, type: :string, repeatable: true, aliases: '-t',
                              description: 'Translation file (repeat for multiple files)' }),
        Definition.new(name: :source_paths, type: :array, default: ['.'], values: nil, yaml_path: %w[source paths],
                       cli: { name: :source, type: :string, repeatable: true, aliases: '-s',
                              description: 'Source file or directory (repeat for multiple paths)' }),
        Definition.new(name: :ignore_patterns, type: :array, default: [], values: nil, yaml_path: %w[source ignore], cli: nil),
        Definition.new(name: :context_files, type: :array, default: [], values: nil, yaml_path: %w[context files],
                       cli: { name: :context_file, type: :string, repeatable: true,
                              description: 'Supplemental context file (repeat for multiple files)' }),
        Definition.new(name: :provider, type: :string, default: 'anthropic',
                       values: %w[anthropic openai openai_compatible], yaml_path: %w[llm provider],
                       cli: { aliases: '-p', description: 'LLM provider', show_default: true }),
        Definition.new(name: :model, type: :string, default: nil, values: nil, yaml_path: %w[llm model],
                       cli: { aliases: '-m', description: 'LLM model to use (provider default when omitted)' }),
        Definition.new(name: :endpoint, type: :string, default: nil, values: nil, yaml_path: %w[llm endpoint],
                       cli: { description: 'Explicit OpenAI-compatible Responses API endpoint' }),
        Definition.new(name: :concurrency, type: :integer, default: 5, values: nil, yaml_path: %w[processing concurrency],
                       cli: { description: 'Number of concurrent requests', show_default: true }),
        Definition.new(name: :context_lines, type: :integer, default: 15, values: nil, yaml_path: %w[processing context_lines], cli: nil),
        Definition.new(name: :max_matches_per_key, type: :integer, default: 3, values: nil,
                       yaml_path: %w[processing max_matches_per_key], cli: nil),
        Definition.new(name: :max_prompt_chars, type: :integer, default: 50_000, values: nil,
                       yaml_path: %w[processing max_prompt_chars],
                       cli: { description: 'Maximum characters sent per LLM prompt', show_default: true }),
        Definition.new(name: :discovery_mode, type: :string, default: 'auto', values: %w[auto translations source],
                       yaml_path: %w[processing discovery_mode],
                       cli: { description: 'How to discover entries: auto, translations, or source', show_default: true }),
        Definition.new(name: :platform, type: :string, default: nil, values: %w[ios android], yaml_path: %w[processing platform],
                       cli: { description: 'Explicit platform override: ios or android' }),
        Definition.new(name: :output_path, type: :string, default: nil, values: nil, yaml_path: %w[output path],
                       cli: { name: :output, aliases: '-o', description: 'Output file path (.csv or .json; format inferred when omitted)' }),
        Definition.new(name: :output_format, type: :string, default: 'csv', values: %w[csv json], yaml_path: %w[output format],
                       cli: { name: :format, aliases: '-f', description: 'Output format', show_default: true,
                              default_note: 'inferred from output path; fallback %s' }),
        Definition.new(name: :output_stdout, type: :boolean, default: false, values: nil,
                       yaml_path: %w[output stdout],
                       cli: { name: :stdout, description: 'Write structured CSV or JSON to stdout' }),
        Definition.new(name: :write_back, type: :boolean, default: false, values: nil, yaml_path: %w[output write_back],
                       cli: { description: 'Write context back to translation files (.strings, .xcstrings, strings.xml)',
                              show_default: true }),
        Definition.new(name: :write_back_to_code, type: :boolean, default: false, values: nil,
                       yaml_path: %w[output write_back_to_code],
                       cli: { description: 'Write context back to Swift source code comment: parameters', show_default: true }),
        Definition.new(name: :context_prefix, type: :string, default: 'Context: ', values: nil, yaml_path: %w[output context_prefix],
                       cli: { description: 'Prefix for generated context comments', show_default: true, quote_default: true }),
        Definition.new(name: :context_mode, type: :string, default: 'replace', values: %w[replace append], yaml_path: %w[output context_mode],
                       cli: { description: 'How to handle existing comments: replace or append', show_default: true }),
        Definition.new(name: :swift_functions, type: :array, default: LocalizationSyntax::DEFAULT_SWIFT_FUNCTIONS,
                       values: nil, yaml_path: %w[swift functions], cli: nil),
        Definition.new(name: :cache_enabled, type: :boolean, default: false, values: nil, yaml_path: %w[cache enabled],
                       cli: { name: :cache, description: 'Enable caching of successful LLM results', show_default: true }),
        Definition.new(name: :cache_dir, type: :string, default: '.i18n-context-generator-cache', values: nil,
                       yaml_path: %w[cache directory],
                       cli: { description: 'Cache directory', show_default: true }),
        Definition.new(name: :dry_run, type: :boolean, default: false, values: nil, yaml_path: nil,
                       cli: { description: 'Show what would be processed without calling the LLM' }),
        Definition.new(name: :key_filter, type: :string, default: nil, values: nil, yaml_path: nil,
                       cli: { name: :key, aliases: '-k', type: :string, repeatable: true,
                              description: 'Key filter pattern (repeatable, supports * wildcard)' }),
        Definition.new(name: :print_config, type: :boolean, default: false, values: nil, yaml_path: nil,
                       cli: { description: 'Print the resolved configuration and exit' }),
        Definition.new(name: :workflow_stage, type: :string, default: 'apply',
                       values: %w[check plan preview_diff apply], yaml_path: %w[workflow stage], cli: nil),
        Definition.new(name: :diff_base, type: :string, default: nil, values: nil, yaml_path: nil,
                       cli: { description: 'Only process keys changed since this git ref (e.g., main, origin/main)' }),
        Definition.new(name: :diff_head, type: :string, default: 'HEAD', values: nil, yaml_path: nil,
                       cli: { description: 'Compare --diff-base to this git ref', show_default: true }),
        Definition.new(name: :start_key, type: :string, default: nil, values: nil, yaml_path: nil,
                       cli: { description: 'Start processing from this key (inclusive)' }),
        Definition.new(name: :end_key, type: :string, default: nil, values: nil, yaml_path: nil,
                       cli: { description: 'Stop processing at this key (inclusive)' }),
        Definition.new(name: :include_file_paths, type: :boolean, default: false, values: nil,
                       yaml_path: %w[privacy include_file_paths],
                       cli: { description: 'Include full source file paths in LLM prompts', show_default: true }),
        Definition.new(name: :include_translation_comments, type: :boolean, default: true, values: nil,
                       yaml_path: %w[privacy include_translation_comments],
                       cli: { description: 'Include translation file comments in LLM prompts', show_default: true }),
        Definition.new(name: :redact_prompts, type: :boolean, default: true, values: nil, yaml_path: %w[privacy redact_prompts],
                       cli: { description: 'Best-effort redact likely secrets and PII from LLM prompts', show_default: true })
      ].freeze

      BY_NAME = DEFINITIONS.to_h { |definition| [definition.name, definition] }.freeze

      module_function

      def definition(name)
        BY_NAME.fetch(name)
      end

      def thor_type(type)
        { string: :string, integer: :numeric, boolean: :boolean }.fetch(type)
      end

      def default(name)
        value = definition(name).default
        value.is_a?(Array) || value.is_a?(Hash) || value.is_a?(String) ? value.dup : value
      end

      def values(name)
        definition(name).values
      end

      def cli_definitions
        DEFINITIONS.select(&:cli?)
      end

      def configured?(yaml, name)
        path = definition(name).yaml_path
        return false unless path

        parent = path[0...-1].reduce(yaml) { |value, key| value.is_a?(Hash) ? value[key] : nil }
        parent.is_a?(Hash) && parent.key?(path.last)
      end

      def value(yaml, name)
        return default(name) unless configured?(yaml, name)

        definition(name).yaml_path.reduce(yaml) { |value, key| value.fetch(key) }
      end

      def validate_document!(yaml, path:)
        explicit_version = yaml.key?('schema_version')
        version = yaml.fetch('schema_version', VERSION)
        raise Error, "Invalid config #{path}: unsupported schema_version #{version.inspect}; expected #{VERSION}" unless version == VERSION

        unknown_messages = []
        unknown_top_level = yaml.keys - DOCUMENT_KEYS
        unknown_messages << "unknown top-level keys: #{unknown_top_level.join(', ')}" if unknown_top_level.any?

        SECTION_KEYS.each do |section, allowed_keys|
          value = yaml[section]
          next unless value.is_a?(Hash)

          unknown = value.keys - allowed_keys
          next if unknown.empty?

          unknown_messages << "unknown #{section} keys: #{unknown.join(', ')}"
        end

        if unknown_messages.any?
          details = unknown_messages.join('; ')
          raise Error, "Invalid config #{path}: #{details}" if explicit_version

          warn "Warning: #{details} ignored in unversioned config #{path}; add schema_version: #{VERSION} to enable strict validation"
        end

        VERSION
      end
    end
  end
end
