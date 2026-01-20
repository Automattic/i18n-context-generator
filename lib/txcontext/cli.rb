# frozen_string_literal: true

require "thor"

module Txcontext
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "extract", "Extract translation context from source code"
    long_desc <<~DESC
      Analyzes source code to extract contextual information for translation keys.
      Uses AI to understand how strings are used in the UI and generates descriptions
      to help translators produce better translations.

      Examples:
        # iOS app
        txcontext extract -t ios/Localizable.strings -s ios/

        # Android app
        txcontext extract -t android/res/values/strings.xml -s android/app/

        # Write context back to source files
        txcontext extract -t Localizable.strings -s . --write-back

        # Use config file
        txcontext extract --config txcontext.yml
    DESC
    option :config, aliases: "-c", desc: "Path to config file (txcontext.yml)"
    option :translations, aliases: "-t", desc: "Translation file(s), comma-separated"
    option :source, aliases: "-s", desc: "Source directory(ies) to search, comma-separated"
    option :output, aliases: "-o", default: "translation-context.csv", desc: "Output file path"
    option :format, aliases: "-f", default: "csv", enum: %w[csv json], desc: "Output format"
    option :provider, aliases: "-p", default: "anthropic", enum: %w[anthropic], desc: "LLM provider"
    option :model, aliases: "-m", desc: "LLM model to use"
    option :keys, aliases: "-k", desc: "Filter keys (comma-separated patterns, supports * wildcard)"
    option :concurrency, type: :numeric, default: 5, desc: "Number of concurrent requests"
    option :dry_run, type: :boolean, default: false, desc: "Show what would be processed without calling LLM"
    option :no_cache, type: :boolean, default: false, desc: "Disable caching"
    option :write_back, type: :boolean, default: false, desc: "Write context back to source translation files (.strings, strings.xml)"
    option :write_back_to_code, type: :boolean, default: false, desc: "Write context back to Swift source code comment: parameters"
    option :diff_base, type: :string, desc: "Only process keys changed since this git ref (e.g., main, origin/main)"
    option :context_prefix, type: :string, default: "Context: ", desc: "Prefix for context comments (use empty string for no prefix)"
    option :context_mode, type: :string, default: "replace", enum: %w[replace append], desc: "How to handle existing comments: replace or append"

    def extract
      validate_options!
      validate_api_key!
      validate_diff_base! if options[:diff_base]

      config = Config.load(options)
      extractor = ContextExtractor.new(config)
      extractor.run
    rescue Txcontext::Error => e
      say_error "Error: #{e.message}"
      exit 1
    rescue Interrupt
      say "\nInterrupted"
      exit 130
    end

    desc "init", "Create a sample config file"
    option :force, type: :boolean, default: false, desc: "Overwrite existing config"

    def init
      config_path = "txcontext.yml"

      if File.exist?(config_path) && !options[:force]
        say_error "Config file already exists. Use --force to overwrite."
        exit 1
      end

      File.write(config_path, sample_config)
      say "Created #{config_path}"
    end

    desc "version", "Show version"
    def version
      say "txcontext #{VERSION}"
    end

    default_task :extract

    private

    def validate_options!
      return if options[:config] && File.exist?(options[:config])

      unless options[:translations]
        say_error "Error: --translations (-t) is required unless using a config file"
        exit 1
      end
    end

    def validate_api_key!
      return if options[:dry_run]

      provider = options[:provider] || "anthropic"
      env_var = case provider
                when "anthropic" then "ANTHROPIC_API_KEY"
                when "openai" then "OPENAI_API_KEY"
                else "#{provider.upcase}_API_KEY"
                end

      return if ENV[env_var]

      say_error "Error: #{env_var} environment variable is required for provider '#{provider}'"
      say_error "Set it with: export #{env_var}=your-api-key"
      exit 1
    end

    def validate_diff_base!
      unless GitDiff.available?
        say_error "Error: --diff-base requires a git repository"
        exit 1
      end

      git_diff = GitDiff.new(base_ref: options[:diff_base])
      unless git_diff.base_ref_exists?
        say_error "Error: git ref '#{options[:diff_base]}' not found"
        say_error "Try: origin/main, main, or a specific commit SHA"
        exit 1
      end
    end

    def say_error(message)
      $stderr.puts message
    end

    def sample_config
      <<~YAML
        # txcontext configuration
        # Extract translation context from mobile app source code

        # Translation files to process
        # Supported formats: .strings (iOS), strings.xml (Android), .json, .yml
        translations:
          # iOS example
          - path: ios/MyApp/Resources/Localizable.strings

          # Android example
          # - path: android/app/src/main/res/values/strings.xml

        # Source code directories to search
        source:
          paths:
            - ios/MyApp/
            # - android/app/src/main/java/
          ignore:
            - "**/Pods/**"
            - "**/build/**"
            - "**/*.generated.*"
            - "**/*Tests*"

        # LLM configuration
        llm:
          provider: anthropic
          model: claude-sonnet-4-20250514
          # API key is read from ANTHROPIC_API_KEY environment variable

        # Processing options
        processing:
          concurrency: 5
          context_lines: 20
          max_matches_per_key: 3

        # Output configuration
        output:
          format: csv
          path: translation-context.csv
          # Set to true to write context comments back to translation files (.strings, strings.xml)
          write_back: false
          # Set to true to write context back to Swift source code comment: parameters
          write_back_to_code: false
          # Prefix for context comments (use empty string for no prefix)
          # context_prefix: "Context: "
          # How to handle existing comments: "replace" or "append"
          # context_mode: replace

        # Swift-specific configuration for write_back_to_code
        swift:
          # Localization functions to update (default shown)
          functions:
            - NSLocalizedString
            - "String(localized:"
            - "Text("
            # Add custom functions like:
            # - "MyLocalizedString("
      YAML
    end
  end
end
