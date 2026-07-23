# frozen_string_literal: true

require 'thor'
require_relative 'config'

module I18nContextGenerator
  # Configuration inspection commands kept separate from extraction options.
  class ConfigCommand < Thor
    desc 'validate [PATH]', 'Validate a client configuration file'
    def validate(path = '.i18n-context-generator.yml')
      Config.from_file(path).validate!
      say "Configuration is valid (schema version #{Config::Schema::VERSION}): #{path}"
    rescue I18nContextGenerator::Error => e
      warn "Error: #{e.message}"
      exit 1
    end
  end

  # Thor-based CLI entry point for the i18n-context-generator command.
  class CLI < Thor
    register ConfigCommand, 'config', 'config SUBCOMMAND', 'Inspect or validate configuration'

    def self.extraction_options
      Config::Schema.cli_definitions.each do |definition|
        option definition.cli_name, **definition.thor_options
      end
      option :translations, type: :string, hide: true,
                            desc: 'Deprecated: comma-separated translation files'
      option :keys, type: :string, hide: true,
                    desc: 'Deprecated: comma-separated key filters'
    end

    def self.exit_on_failure?
      true
    end

    desc 'extract', 'Extract translation context from source code'
    long_desc <<~DESC
      Analyzes source code to extract contextual information for translation keys.
      Uses AI to understand how strings are used in the UI and generates descriptions
      to help translators produce better translations.

      Examples:
        # iOS app
        i18n-context-generator extract -t ios/Localizable.strings -s ios/

        # Android app
        i18n-context-generator extract -t android/res/values/strings.xml -s android/app/

        # Write context back to source files
        i18n-context-generator extract -t Localizable.strings -s . --write-back

        # Use config file
        i18n-context-generator extract --config .i18n-context-generator.yml
    DESC
    extraction_options

    def extract
      run_workflow('apply')
    end

    desc 'check', 'Validate and check source usage without calling the LLM'
    extraction_options
    def check
      run_workflow('check')
    end

    desc 'plan', 'Show selected keys and destinations without calling the LLM'
    extraction_options
    def plan
      run_workflow('plan')
    end

    map 'preview-diff' => :preview_diff
    desc 'preview-diff', 'Generate and preview write-back patches without modifying files'
    extraction_options
    def preview_diff
      run_workflow('preview_diff')
    end

    desc 'apply', 'Generate context and apply the configured destinations'
    extraction_options
    def apply
      run_workflow('apply')
    end

    desc 'init', 'Create a sample config file'
    option :force, type: :boolean, default: false, desc: 'Overwrite existing config'

    def init
      config_path = '.i18n-context-generator.yml'

      if File.exist?(config_path) && !options[:force]
        say_error 'Config file already exists. Use --force to overwrite.'
        exit 1
      end

      File.write(config_path, sample_config)
      say "Created #{config_path}"
    end

    desc 'version', 'Show version'
    def version
      say "i18n-context-generator #{VERSION}"
    end

    default_task :extract

    private

    def run_workflow(stage)
      validate_options!
      warn_deprecated_list_options!
      config = Config.load(options)
      config.merge_cli(workflow_stage: stage)
      config.validate!
      if config.print_config
        puts YAML.dump(config.to_h)
        return
      end
      validate_destination!(config)
      validate_api_key!(provider: config.provider, dry_run: config.dry_run) unless %w[check plan].include?(config.workflow_stage)
      validate_diff_range!(base_ref: config.diff_base, head_ref: config.diff_head) if config.diff_base
      extractor = ContextExtractor.new(config)
      extractor.run
      fail_if_extraction_errors!(extractor)
    rescue I18nContextGenerator::Error => e
      say_error "Error: #{e.message}"
      exit 1
    rescue Interrupt
      say "\nInterrupted"
      exit 130
    end

    def validate_options!
      return if options[:print_config]
      return if options[:config]

      return if options[:translation] || options[:translations]
      return if options[:discovery_mode] == 'source' && options[:source]

      say_error 'Error: --translation (-t) is required unless using a config file or --discovery-mode source with --source'
      exit 1
    end

    def warn_deprecated_list_options!
      say_error 'Warning: --translations is deprecated; repeat --translation instead.' if options[:translations]
      say_error 'Warning: --keys is deprecated; repeat --key instead.' if options[:keys]

      repeatable_values = Array(options[:translation]) + Array(options[:source]) + Array(options[:key])
      return unless repeatable_values.any? { |value| value.include?(',') }

      say_error 'Warning: comma-separated CLI lists are deprecated; repeat the singular flag instead.'
    end

    def validate_api_key!(provider: nil, dry_run: nil)
      return if dry_run.nil? ? options[:dry_run] : dry_run

      provider ||= options[:provider] || 'anthropic'
      return if provider == 'openai_compatible'

      env_var = case provider
                when 'anthropic' then 'ANTHROPIC_API_KEY'
                when 'openai' then 'OPENAI_API_KEY'
                else "#{provider.upcase}_API_KEY"
                end

      return if ENV[env_var]

      say_error "Error: #{env_var} environment variable is required for provider '#{provider}'"
      say_error "Set it with: export #{env_var}=your-api-key"
      exit 1
    end

    def validate_destination!(config)
      return if %w[check plan].include?(config.workflow_stage)
      return if config.dry_run
      return if config.output_path || config.write_back || config.write_back_to_code

      raise Error, 'A non-dry extraction requires --output, --write-back, or --write-back-to-code'
    end

    def validate_diff_range!(base_ref: options[:diff_base], head_ref: options[:diff_head] || 'HEAD')
      unless GitDiff.available?
        say_error 'Error: --diff-base requires a git repository'
        exit 1
      end

      git_diff = GitDiff.new(base_ref: base_ref, head_ref: head_ref)
      unless git_diff.base_ref_exists?
        say_error "Error: git ref '#{base_ref}' not found"
        say_error 'Try: origin/main, main, or a specific commit SHA'
        exit 1
      end
      return if git_diff.head_ref_exists?

      say_error "Error: git ref '#{head_ref}' not found"
      say_error 'Try: HEAD, a branch name, or a specific commit SHA'
      exit 1
    end

    def say_error(message)
      warn message
    end

    def fail_if_extraction_errors!(extractor)
      return unless extractor.errors.any?

      say_error "Completed with #{extractor.errors.size} extraction error(s)."
      exit 1
    end

    def sample_config
      schema = Config::Schema
      swift_functions = schema.default(:swift_functions).map { |function| "    - #{function.inspect}" }.join("\n")

      <<~YAML
        # i18n-context-generator configuration
        # Extract translation context from mobile app source code
        schema_version: #{schema.default(:schema_version)}

        # Translation files to process
        # Supported formats: .strings/.xcstrings (iOS), strings.xml (Android), .json, .yml
        translations:
          # iOS example
          - path: ios/MyApp/Resources/Localizable.strings

          # Android example
          # - path: android/app/src/main/res/values/strings.xml

          # YAML locale roots are stripped only when configured explicitly
          # - path: config/translations.yml
          #   locale: en

        # Source code directories to search
        source:
          paths:
            - ios/MyApp/
            # - android/app/src/main/java/
          # These entries extend the built-in dependency, build, and test ignores.
          ignore:
            - "**/*.generated.*"

        # LLM configuration
        llm:
          provider: #{schema.default(:provider)}
          # model: provider-specific default
          # For provider: openai_compatible, set an explicit model and endpoint.
          # endpoint: http://127.0.0.1:11434/v1/responses
          # API key is read from the matching provider env var
          # (ANTHROPIC_API_KEY or OPENAI_API_KEY)

        # Processing options
        processing:
          # Optional explicit platform override: ios or android
          # platform: ios
          # Discovery mode: auto, translations, or source
          discovery_mode: #{schema.default(:discovery_mode)}
          concurrency: #{schema.default(:concurrency)}
          context_lines: #{schema.default(:context_lines)}
          max_matches_per_key: #{schema.default(:max_matches_per_key)}
          # Hard character limit for each prompt; oversized context is truncated
          max_prompt_chars: #{schema.default(:max_prompt_chars)}

        # Optional local cache. Only successful results are cached.
        cache:
          enabled: #{schema.default(:cache_enabled)}
          directory: #{schema.default(:cache_dir)}

        # Default workflow for programmatic/config-file runs.
        workflow:
          stage: #{schema.default(:workflow_stage)}

        # Output configuration
        output:
          format: #{schema.default(:output_format)}
          path: translation-context.csv
          # Write the selected CSV/JSON format to stdout instead of a file.
          stdout: #{schema.default(:output_stdout)}
          # Set to true to write context comments back to translation files
          # (.strings, .xcstrings, strings.xml)
          write_back: #{schema.default(:write_back)}
          # Set to true to write context back to Swift source code comment: parameters
          write_back_to_code: #{schema.default(:write_back_to_code)}
          # Prefix for context comments (use empty string for no prefix)
          # context_prefix: #{schema.default(:context_prefix).inspect}
          # How to handle existing comments: "replace" or "append"
          # context_mode: #{schema.default(:context_mode)}

        # Swift-specific extraction and write-back configuration
        swift:
          # Custom entries extend the built-in localization functions (defaults shown)
          functions:
        #{swift_functions}
            # Add custom functions like:
            # - "MyLocalizedString("

        # Prompt privacy controls
        privacy:
          # Include full source paths in prompts sent to the LLM (default: false)
          include_file_paths: #{schema.default(:include_file_paths)}
          # Include translation file comments in prompts (default: true)
          include_translation_comments: #{schema.default(:include_translation_comments)}
          # Best-effort redact likely secrets, URLs, and emails before sending prompts.
          # Source snippets still leave the machine when using a remote provider.
          redact_prompts: #{schema.default(:redact_prompts)}
      YAML
    end
  end
end
