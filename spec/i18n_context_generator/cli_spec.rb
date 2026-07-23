# frozen_string_literal: true

require 'i18n_context_generator/cli'

RSpec.describe I18nContextGenerator::CLI do
  def with_env(var, value)
    original = ENV.fetch(var, nil)
    value.nil? ? ENV.delete(var) : ENV[var] = value
    yield
  ensure
    original.nil? ? ENV.delete(var) : ENV[var] = original
  end

  # rubocop:disable Style/RaiseArgs
  def raise_system_exit(status)
    raise SystemExit.new(status)
  end
  # rubocop:enable Style/RaiseArgs

  it 'exits on failure and allows the OpenAI provider in the CLI option enum' do
    expect(described_class.exit_on_failure?).to be true

    provider_option = described_class.commands.fetch('extract').options.fetch(:provider)

    expect(provider_option.enum).to eq(%w[anthropic openai openai_compatible])
  end

  it 'exposes repeatable singular translation, source, context file, and key options' do
    options = described_class.commands.fetch('extract').options

    expect(options.fetch(:translation).repeatable).to be(true)
    expect(options.fetch(:source).repeatable).to be(true)
    expect(options.fetch(:context_file).repeatable).to be(true)
    expect(options.fetch(:key).repeatable).to be(true)
    expect(options.fetch(:translation).aliases).to include('-t')
    expect(options.fetch(:key).aliases).to include('-k')
  end

  it 'registers explicit check, plan, preview-diff, and apply workflows' do
    expect(described_class.commands.keys).to include('check', 'plan', 'preview_diff', 'apply')
    expect(described_class.map['preview-diff']).to eq(:preview_diff)
  end

  describe 'option validation' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:exit) { |status| raise_system_exit(status) }
      allow(cli).to receive(:say_error)
    end

    it 'accepts an existing config file without requiring translations' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.i18n-context-generator.yml')
        File.write(config_path, "translations: []\n")

        allow(cli).to receive(:options).and_return(config: config_path, translations: nil)

        expect { cli.send(:validate_options!) }.not_to raise_error
      end
    end

    it 'accepts source-only discovery when source paths are provided' do
      allow(cli).to receive(:options).and_return(
        config: nil,
        translations: nil,
        discovery_mode: 'source',
        source: './Sources'
      )

      expect { cli.send(:validate_options!) }.not_to raise_error
    end

    it 'requires translations when no config file is provided' do
      allow(cli).to receive(:options).and_return(config: nil, translations: nil)

      expect { cli.send(:validate_options!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(/--translation \(-t\) is required/)
    end
  end

  describe 'list deprecations' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:say_error)
    end

    it 'warns only for legacy plural flags' do
      allow(cli).to receive(:options).and_return(
        translations: 'First.strings,Second.strings',
        keys: 'settings.*,profile.*',
        source: ['Sources,Shared'],
        translation: ['Resources,Legacy.xcstrings']
      )

      cli.send(:warn_deprecated_list_options!)

      expect(cli).to have_received(:say_error).with(/--translations is deprecated/)
      expect(cli).to have_received(:say_error).with(/--keys is deprecated/)
      expect(cli).to have_received(:say_error).exactly(2).times
    end
  end

  describe 'API key validation' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:exit) { |status| raise_system_exit(status) }
      allow(cli).to receive(:say_error)
    end

    it 'skips API key validation in dry-run mode' do
      allow(cli).to receive(:options).and_return(dry_run: true)

      expect { cli.send(:validate_api_key!) }.not_to raise_error
    end

    it 'requires OPENAI_API_KEY for the OpenAI provider' do
      with_env('OPENAI_API_KEY', nil) do
        allow(cli).to receive(:options).and_return(dry_run: false, provider: 'openai')

        expect { cli.send(:validate_api_key!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        expect(cli).to have_received(:say_error).with(/OPENAI_API_KEY environment variable is required/)
      end
    end

    it 'does not forward or require the OpenAI key for compatible endpoints' do
      with_env('OPENAI_API_KEY', nil) do
        allow(cli).to receive(:options).and_return(
          dry_run: false,
          provider: 'openai_compatible'
        )

        expect { cli.send(:validate_api_key!) }.not_to raise_error
      end
    end
  end

  describe 'destination validation' do
    let(:cli) { described_class.allocate }

    it 'allows dry runs without a destination' do
      config = I18nContextGenerator::Config.new(dry_run: true)

      expect { cli.send(:validate_destination!, config) }.not_to raise_error
    end

    it 'allows each durable destination' do
      configurations = [
        I18nContextGenerator::Config.new(output_path: 'context.csv'),
        I18nContextGenerator::Config.new(write_back: true),
        I18nContextGenerator::Config.new(write_back_to_code: true)
      ]

      configurations.each do |config|
        expect { cli.send(:validate_destination!, config) }.not_to raise_error
      end
    end

    it 'rejects paid extraction without a destination' do
      config = I18nContextGenerator::Config.new

      expect { cli.send(:validate_destination!, config) }
        .to raise_error(I18nContextGenerator::Error, /requires --output, --write-back, or --write-back-to-code/)
    end
  end

  describe 'sample configuration' do
    it 'describes client ignores as additions without repeating built-in defaults' do
      sample = described_class.allocate.send(:sample_config)

      expect(sample).to include('extend the built-in dependency, build, and test ignores')
      expect(sample).to include('- "**/*.generated.*"')
      expect(sample).to include('# - path: config/translations.yml', '#   locale: en')
      expect(sample).to include('# platform: ios')
      expect(sample).to include('max_prompt_chars: 50000')
      expect(sample).to include("context:\n  files:")
      expect(sample).to include('- GLOSSARY.md')
      expect(sample).to include('enabled: false', 'directory: .i18n-context-generator-cache')
      expect(sample).to include('Best-effort redact likely secrets')
      expect(sample).to include('Source snippets still leave the machine')
      expect(sample).not_to include('- "**/Pods/**"', '- "**/build/**"', '- "**/*Tests*"')
    end

    it 'uses schema defaults and emits valid YAML' do
      sample = described_class.allocate.send(:sample_config)
      parsed = YAML.safe_load(sample)
      schema = I18nContextGenerator::Config::Schema

      expect(parsed.dig('llm', 'provider')).to eq(schema.default(:provider))
      expect(parsed['schema_version']).to eq(schema.default(:schema_version))
      expect(parsed.dig('processing', 'concurrency')).to eq(schema.default(:concurrency))
      expect(parsed.dig('processing', 'max_prompt_chars')).to eq(schema.default(:max_prompt_chars))
      expect(parsed.dig('cache', 'enabled')).to eq(schema.default(:cache_enabled))
      expect(parsed.dig('cache', 'directory')).to eq(schema.default(:cache_dir))
      expect(parsed.dig('swift', 'functions')).to eq(schema.default(:swift_functions))
      expect(parsed.dig('privacy', 'redact_prompts')).to eq(schema.default(:redact_prompts))
      expect(parsed.dig('context', 'files')).to eq(schema.default(:context_files))
      expect(sample).to include('Custom entries extend the built-in localization functions')
    end
  end

  describe I18nContextGenerator::ConfigCommand do
    it 'uses non-zero exit status for Thor command failures' do
      expect(described_class.exit_on_failure?).to be(true)
    end

    it 'validates a schema-versioned configuration file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'config.yml')
        File.write(path, "schema_version: 1\nsource:\n  paths:\n    - .\n")
        command = described_class.new

        expect { command.validate(path) }
          .to output(/Configuration is valid \(schema version 1\)/).to_stdout
      end
    end
  end

  describe 'configuration schema' do
    it 'drives CLI types, enums, and default descriptions' do
      options = described_class.commands.fetch('extract').options
      schema = I18nContextGenerator::Config::Schema

      expect(options.fetch(:provider).enum).to eq(schema.values(:provider))
      expect(options.fetch(:concurrency).type).to eq(:numeric)
      expect(options.fetch(:concurrency).description).to include("default: #{schema.default(:concurrency)}")
      expect(options.fetch(:redact_prompts).description).to include("default: #{schema.default(:redact_prompts)}")
    end
  end

  describe '#extract' do
    let(:cli) { described_class.allocate }

    it 'honors a workflow stage loaded from configuration' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        workflow_stage: 'check',
        output_path: 'context.csv'
      )
      extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, errors: [])
      allow(cli).to receive(:options).and_return(
        config: '.i18n-context-generator.yml',
        translation: nil,
        translations: nil,
        diff_base: nil
      )
      allow(I18nContextGenerator::Config).to receive(:load).with(cli.options).and_return(config)
      allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

      expect { cli.extract }.not_to raise_error
      expect(config.workflow_stage).to eq('check')
    end

    it 'lets an explicit workflow command override the configured stage' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        workflow_stage: 'check',
        output_path: 'context.csv'
      )
      extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, errors: [])
      allow(cli).to receive(:options).and_return(
        config: '.i18n-context-generator.yml',
        translation: nil,
        translations: nil,
        diff_base: nil
      )
      allow(cli).to receive(:validate_api_key!)
      allow(I18nContextGenerator::Config).to receive(:load).with(cli.options).and_return(config)
      allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

      expect { cli.apply }.not_to raise_error
      expect(config.workflow_stage).to eq('apply')
    end

    it 'uses the provider from the loaded config when validating API keys' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.i18n-context-generator.yml')
        File.write(config_path, "llm:\n  provider: openai\n")

        config = I18nContextGenerator::Config.new(translations: [], provider: 'openai', output_path: 'context.csv')
        extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, errors: [])

        allow(cli).to receive(:options).and_return(
          config: config_path,
          translations: nil,
          provider: nil,
          dry_run: false,
          diff_base: nil
        )
        allow(I18nContextGenerator::Config).to receive(:load).with(cli.options).and_return(config)
        allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

        with_env('OPENAI_API_KEY', 'test-openai-key') do
          with_env('ANTHROPIC_API_KEY', nil) do
            expect { cli.extract }.not_to raise_error
          end
        end
      end
    end

    it 'exits non-zero when extraction completes with errors' do
      Dir.mktmpdir do |dir|
        translation_path = File.join(dir, 'Localizable.strings')
        File.write(translation_path, '"settings.title" = "Settings";')
        config = I18nContextGenerator::Config.new(
          translations: [translation_path],
          output_path: 'context.csv',
          dry_run: false
        )
        errored_result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
          key: 'settings.title',
          text: 'Settings',
          description: 'API request failed',
          error: 'timeout'
        )
        extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, errors: [errored_result])

        allow(cli).to receive(:options).and_return(
          config: nil,
          translations: translation_path,
          provider: 'anthropic',
          dry_run: false,
          diff_base: nil
        )
        allow(cli).to receive(:say_error)
        allow(cli).to receive(:exit) { |status| raise_system_exit(status) }
        allow(I18nContextGenerator::Config).to receive(:load).with(cli.options).and_return(config)
        allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

        with_env('ANTHROPIC_API_KEY', 'test-anthropic-key') do
          expect { cli.extract }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end

        expect(cli).to have_received(:say_error).with('Completed with 1 extraction error(s).')
      end
    end

    it 'validates diff-base in source mode' do
      Dir.mktmpdir do |source_dir|
        config = I18nContextGenerator::Config.new(
          translations: [],
          source_paths: [source_dir],
          discovery_mode: 'source',
          diff_base: 'origin/main',
          dry_run: true
        )
        extractor = instance_double(I18nContextGenerator::ContextExtractor, run: nil, errors: [])

        allow(cli).to receive(:options).and_return(
          config: nil,
          translations: nil,
          discovery_mode: 'source',
          source: source_dir,
          provider: 'anthropic',
          dry_run: true,
          diff_base: 'origin/main'
        )
        allow(cli).to receive(:validate_diff_range!)
        allow(I18nContextGenerator::Config).to receive(:load).with(cli.options).and_return(config)
        allow(I18nContextGenerator::ContextExtractor).to receive(:new).with(config).and_return(extractor)

        expect { cli.extract }.not_to raise_error
        expect(cli).to have_received(:validate_diff_range!).with(base_ref: 'origin/main', head_ref: 'HEAD')
      end
    end
  end

  describe 'diff range validation' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:exit) { |status| raise_system_exit(status) }
      allow(cli).to receive(:say_error)
      allow(cli).to receive(:options).and_return(diff_base: 'origin/main', diff_head: 'feature/head')
    end

    it 'requires a git repository' do
      allow(I18nContextGenerator::GitDiff).to receive(:available?).and_return(false)

      expect { cli.send(:validate_diff_range!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(/requires a git repository/)
    end

    it 'requires the specified git ref to exist' do
      git_diff = instance_double(I18nContextGenerator::GitDiff, base_ref_exists?: false)
      allow(I18nContextGenerator::GitDiff).to receive(:available?).and_return(true)
      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'feature/head').and_return(git_diff)

      expect { cli.send(:validate_diff_range!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(%r{git ref 'origin/main' not found})
    end

    it 'requires the specified head ref to exist' do
      git_diff = instance_double(
        I18nContextGenerator::GitDiff,
        base_ref_exists?: true,
        head_ref_exists?: false
      )
      allow(I18nContextGenerator::GitDiff).to receive(:available?).and_return(true)
      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'feature/head').and_return(git_diff)

      expect { cli.send(:validate_diff_range!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(%r{git ref 'feature/head' not found})
    end
  end
end
