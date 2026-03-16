# frozen_string_literal: true

RSpec.describe Txcontext::LLM::Anthropic do
  around do |example|
    original_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
    ENV['ANTHROPIC_API_KEY'] = 'test-anthropic-key'
    example.run
    ENV['ANTHROPIC_API_KEY'] = original_api_key
  end

  describe '#generate_context' do
    let(:client) { described_class.new }
    let(:response_body) do
      {
        content: [
          {
            type: 'text',
            text: '{"description":"Primary save action","ui_element":"button","tone":"neutral","max_length":12}'
          }
        ]
      }.to_json
    end
    let(:response) do
      instance_double(
        Net::HTTPOK,
        code: '200',
        body: response_body
      )
    end

    it 'passes the configured Anthropic model through unchanged' do
      allow(client).to receive(:post_json) do |uri:, headers:, body:, **_kwargs|
        expect(uri.to_s).to eq(described_class::API_URL)
        expect(headers).to eq(
          'anthropic-version' => described_class::ANTHROPIC_VERSION,
          'x-api-key' => 'test-anthropic-key'
        )
        expect(body[:model]).to eq('claude-sonnet-4-6')
        expect(body[:system]).to eq(Txcontext::LLM::Client::SYSTEM_PROMPT)
        response
      end

      result = client.generate_context(
        key: 'common.save',
        text: 'Save',
        matches: [],
        model: 'claude-sonnet-4-6'
      )

      expect(client).to have_received(:post_json)
      expect(result.description).to eq('Primary save action')
      expect(result.ui_element).to eq('button')
      expect(result.tone).to eq('neutral')
      expect(result.max_length).to eq(12)
      expect(result.error).to be_nil
    end
  end
end
