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

    expect(provider_option.enum).to eq(%w[anthropic openai])
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
      expect(cli).to have_received(:say_error).with(/--translations \(-t\) is required/)
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
      expect(sample).to include('enabled: false', 'directory: .i18n-context-generator-cache')
      expect(sample).to include('Best-effort redact likely secrets')
      expect(sample).to include('Source snippets still leave the machine')
      expect(sample).not_to include('- "**/Pods/**"', '- "**/build/**"', '- "**/*Tests*"')
    end
  end

  describe '#extract' do
    let(:cli) { described_class.allocate }

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
