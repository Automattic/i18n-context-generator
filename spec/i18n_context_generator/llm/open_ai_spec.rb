# frozen_string_literal: true

RSpec.describe I18nContextGenerator::LLM::OpenAI do
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
        status: 'completed',
        output: [
          {
            type: 'message',
            content: [
              {
                type: 'output_text',
                text: '{"description":"Navigation title for settings","ui_element":"title","tone":"neutral",' \
                      '"max_length":18,"confidence":"medium","ambiguity_reason":"Only one usage was supplied"}'
              }
            ]
          }
        ],
        usage: { input_tokens: 200, output_tokens: 40 }
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
      supplemental_context = [
        I18nContextGenerator::ContextSource.new(
          kind: :runtime,
          name: 'Pull request title',
          content: 'Clarify the settings title'
        )
      ]
      allow(client).to receive(:post_json) do |uri:, headers:, body:, **_kwargs|
        expect(uri.to_s).to eq(described_class::API_URL)
        expect(headers).to eq('Authorization' => 'Bearer test-openai-key')
        expect(body[:model]).to eq('gpt-4.1-mini')
        expect(body[:store]).to be(false)
        expect(body[:max_output_tokens]).to eq(I18nContextGenerator::LLM::Client::MAX_OUTPUT_TOKENS)
        expect(body[:instructions]).to eq(I18nContextGenerator::LLM::Client::SYSTEM_PROMPT)
        expect(body[:input]).to include('settings.title')
        expect(body[:input]).to include('Pull request title', 'Clarify the settings title')
        expect(body.dig(:text, :format, :type)).to eq('json_schema')
        expect(body.dig(:text, :format, :schema, :required)).to include('description')
        response
      end

      result = client.generate_context(
        key: 'settings.title',
        text: 'Settings',
        matches: [],
        model: 'gpt-4.1-mini',
        supplemental_context: supplemental_context
      )

      expect(client).to have_received(:post_json)
      expect(result.description).to eq('Navigation title for settings')
      expect(result.ui_element).to eq('title')
      expect(result.tone).to eq('neutral')
      expect(result.max_length).to eq(18)
      expect(result.confidence).to eq('medium')
      expect(result.ambiguity_reason).to eq('Only one usage was supplied')
      expect(result).to have_attributes(
        input_tokens: 200,
        output_tokens: 40,
        request_count: 1,
        retries: 0
      )
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

    it 'returns explicit errors for incomplete responses and refusals' do
      response_bodies = [
        { status: 'incomplete', incomplete_details: { reason: 'max_output_tokens' }, output: [] },
        {
          status: 'completed',
          output: [
            { type: 'message', content: [{ type: 'refusal', refusal: 'Cannot process this input.' }] }
          ]
        }
      ]
      allow(client).to receive(:post_json) do
        body = response_bodies.shift
        instance_double(Net::HTTPOK, code: '200', body: body.to_json)
      end

      incomplete = client.generate_context(key: 'one', text: 'One', matches: [])
      refusal = client.generate_context(key: 'two', text: 'Two', matches: [])

      expect(incomplete).to have_attributes(description: 'Incomplete response', error: /max_output_tokens/)
      expect(refusal).to have_attributes(description: 'Provider refused request', error: /Cannot process/)
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

    it 'preserves request telemetry for exhausted retries and malformed responses' do
      allow(client).to receive(:sleep)
      allow(client).to receive(:post_json).and_raise(Errno::ECONNRESET, 'reset')

      exhausted = client.generate_context(key: 'one', text: 'One', matches: [])

      expect(exhausted).to have_attributes(
        description: 'API request failed',
        request_count: 3,
        retries: 2,
        error: /reset/
      )

      malformed_response = instance_double(Net::HTTPOK, code: '200', body: '{invalid')
      allow(client).to receive(:post_json).and_return(malformed_response)

      malformed = client.generate_context(key: 'two', text: 'Two', matches: [])

      expect(malformed).to have_attributes(
        description: 'API request failed',
        request_count: 1,
        retries: 0,
        error: /expected object key|unexpected character|unexpected token|parse/i
      )
    end
  end
end
