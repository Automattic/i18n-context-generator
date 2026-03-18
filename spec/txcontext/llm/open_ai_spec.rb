# frozen_string_literal: true

RSpec.describe Txcontext::LLM::OpenAI do
  around do |example|
    original_api_key = ENV.fetch('OPENAI_API_KEY', nil)
    ENV['OPENAI_API_KEY'] = 'test-openai-key'
    example.run
    ENV['OPENAI_API_KEY'] = original_api_key
  end

  describe '#generate_context' do
    let(:client) { described_class.new }
    let(:response_body) do
      {
        output: [
          {
            type: 'message',
            content: [
              {
                type: 'output_text',
                text: '{"description":"Navigation title for settings","ui_element":"title","tone":"neutral","max_length":18}'
              }
            ]
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

    it 'sends a structured Responses API request and parses the result' do
      allow(client).to receive(:post_json) do |uri:, headers:, body:, **_kwargs|
        expect(uri.to_s).to eq(described_class::API_URL)
        expect(headers).to eq('Authorization' => 'Bearer test-openai-key')
        expect(body[:model]).to eq('gpt-4.1-mini')
        expect(body[:store]).to be(false)
        expect(body[:instructions]).to eq(Txcontext::LLM::Client::SYSTEM_PROMPT)
        expect(body[:input]).to include('settings.title')
        expect(body.dig(:text, :format, :type)).to eq('json_schema')
        expect(body.dig(:text, :format, :schema, :required)).to include('description')
        response
      end

      result = client.generate_context(
        key: 'settings.title',
        text: 'Settings',
        matches: [],
        model: 'gpt-4.1-mini'
      )

      expect(client).to have_received(:post_json)
      expect(result.description).to eq('Navigation title for settings')
      expect(result.ui_element).to eq('title')
      expect(result.tone).to eq('neutral')
      expect(result.max_length).to eq(18)
      expect(result.error).to be_nil
    end

    it 'uses the default model when none is specified' do
      allow(client).to receive(:post_json) do |body:, **_kwargs|
        expect(body[:model]).to eq(described_class::DEFAULT_MODEL)
        response
      end

      client.generate_context(key: 'ok', text: 'OK', matches: [])

      expect(client).to have_received(:post_json)
    end
  end
end
