# frozen_string_literal: true

RSpec.describe I18nContextGenerator::LLM::Anthropic do
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
        stop_reason: 'end_turn',
        content: [
          {
            type: 'text',
            text: '{"description":"Primary save action","ui_element":"button","tone":"neutral","max_length":12,' \
                  '"confidence":"high","ambiguity_reason":null}'
          }
        ],
        usage: { input_tokens: 120, output_tokens: 30 }
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
        expect(body[:system]).to eq(I18nContextGenerator::LLM::Client::SYSTEM_PROMPT)
        expect(body.dig(:output_config, :format, :type)).to eq('json_schema')
        expect(body.dig(:output_config, :format, :schema, :required)).to include('description')
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
      expect(result.confidence).to eq('high')
      expect(result).to have_attributes(
        input_tokens: 120,
        output_tokens: 30,
        request_count: 1,
        retries: 0
      )
      expect(result.error).to be_nil
    end

    it 'rejects refusals and token-truncated successful HTTP responses' do
      response_bodies = [
        { stop_reason: 'refusal', content: [{ type: 'text', text: 'I cannot help.' }] },
        { stop_reason: 'max_tokens', content: [{ type: 'text', text: '{"description":' }] }
      ]
      allow(client).to receive(:post_json) do
        body = response_bodies.shift
        instance_double(Net::HTTPOK, code: '200', body: body.to_json)
      end

      refusal = client.generate_context(key: 'one', text: 'One', matches: [])
      incomplete = client.generate_context(key: 'two', text: 'Two', matches: [])

      expect(refusal).to have_attributes(description: 'Provider refused request', error: /refused/)
      expect(incomplete).to have_attributes(description: 'Incomplete response', error: /max_tokens/)
    end

    it 'reports local prompt preparation failures without making an API request' do
      allow(client).to receive(:post_json)

      result = client.generate_context(
        key: 'common.save',
        text: 'Save',
        matches: [],
        max_prompt_chars: 1_999
      )

      expect(result).to have_attributes(
        description: 'Prompt preparation failed',
        error: /max_prompt_chars must be an integer/
      )
      expect(client).not_to have_received(:post_json)
    end

    it 'preserves request telemetry when transient failures exhaust retries' do
      allow(client).to receive(:sleep)
      allow(client).to receive(:post_json).and_raise(Net::ReadTimeout, 'timed out')

      result = client.generate_context(key: 'common.save', text: 'Save', matches: [])

      expect(result).to have_attributes(
        description: 'API request failed',
        request_count: 3,
        retries: 2,
        error: /timed out/
      )
    end
  end
end
