# frozen_string_literal: true

require 'txcontext/cli'

RSpec.describe Txcontext::CLI do
  def with_env(var, value)
    original = ENV.fetch(var, nil)
    value.nil? ? ENV.delete(var) : ENV[var] = value
    yield
  ensure
    original.nil? ? ENV.delete(var) : ENV[var] = original
  end

  it 'exits on failure and allows the OpenAI provider in the CLI option enum' do
    expect(described_class.exit_on_failure?).to be true

    provider_option = described_class.commands.fetch('extract').options.fetch(:provider)

    expect(provider_option.enum).to eq(%w[anthropic openai])
  end

  describe 'option validation' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:exit) { |status| raise SystemExit.new(status) }
      allow(cli).to receive(:say_error)
    end

    it 'accepts an existing config file without requiring translations' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.txcontext.yml')
        File.write(config_path, "translations: []\n")

        allow(cli).to receive(:options).and_return(config: config_path, translations: nil)

        expect { cli.send(:validate_options!) }.not_to raise_error
      end
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
      allow(cli).to receive(:exit) { |status| raise SystemExit.new(status) }
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

  describe 'diff-base validation' do
    let(:cli) { described_class.allocate }

    before do
      allow(cli).to receive(:exit) { |status| raise SystemExit.new(status) }
      allow(cli).to receive(:say_error)
      allow(cli).to receive(:options).and_return(diff_base: 'origin/main')
    end

    it 'requires a git repository' do
      allow(Txcontext::GitDiff).to receive(:available?).and_return(false)

      expect { cli.send(:validate_diff_base!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(/requires a git repository/)
    end

    it 'requires the specified git ref to exist' do
      git_diff = instance_double(Txcontext::GitDiff, base_ref_exists?: false)
      allow(Txcontext::GitDiff).to receive(:available?).and_return(true)
      allow(Txcontext::GitDiff).to receive(:new).with(base_ref: 'origin/main').and_return(git_diff)

      expect { cli.send(:validate_diff_base!) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      expect(cli).to have_received(:say_error).with(/git ref 'origin\/main' not found/)
    end
  end
end
