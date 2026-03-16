# frozen_string_literal: true

require 'txcontext/cli'

RSpec.describe Txcontext::CLI do
  it 'allows the OpenAI provider in the CLI option enum' do
    provider_option = described_class.commands.fetch('extract').options.fetch(:provider)

    expect(provider_option.enum).to eq(%w[anthropic openai])
  end
end
