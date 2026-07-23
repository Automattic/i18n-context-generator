# frozen_string_literal: true

RSpec.describe I18nContextGenerator::LLM::OpenAICompatible do
  around do |example|
    original_compatible_key = ENV.fetch('OPENAI_COMPATIBLE_API_KEY', nil)
    original_openai_key = ENV.fetch('OPENAI_API_KEY', nil)
    ENV.delete('OPENAI_COMPATIBLE_API_KEY')
    ENV['OPENAI_API_KEY'] = 'must-not-be-forwarded'
    example.run
  ensure
    ENV['OPENAI_COMPATIBLE_API_KEY'] = original_compatible_key
    ENV['OPENAI_API_KEY'] = original_openai_key
  end

  it 'uses only the explicit endpoint and never inherits the OpenAI credential' do
    client = described_class.new(endpoint: 'http://127.0.0.1:11434/v1/responses')
    response_body = {
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [
            {
              type: 'output_text',
              text: '{"description":"Local context","ui_element":null,"tone":null,"max_length":null,' \
                    '"confidence":"high","ambiguity_reason":null}'
            }
          ]
        }
      ],
      usage: { input_tokens: 10, output_tokens: 5 }
    }.to_json
    response = instance_double(Net::HTTPOK, code: '200', body: response_body)

    allow(client).to receive(:post_json) do |uri:, headers:, body:, **_kwargs|
      expect(uri.to_s).to eq('http://127.0.0.1:11434/v1/responses')
      expect(headers).to eq({})
      expect(body[:model]).to eq('local-model')
      response
    end

    result = client.generate_context(
      key: 'settings.title',
      text: 'Settings',
      matches: [],
      model: 'local-model'
    )

    expect(result).to have_attributes(
      description: 'Local context',
      confidence: 'high',
      request_count: 1
    )
  end

  it 'uses its separate optional credential when configured' do
    ENV['OPENAI_COMPATIBLE_API_KEY'] = 'local-endpoint-key'
    client = described_class.new(endpoint: 'https://llm.example.test/v1/responses')
    response = instance_double(Net::HTTPUnauthorized, code: '401', body: '{}')

    allow(client).to receive(:post_json) do |headers:, **_kwargs|
      expect(headers).to eq('Authorization' => 'Bearer local-endpoint-key')
      response
    end

    client.generate_context(key: 'key', text: 'Text', matches: [], model: 'local-model')

    expect(client).to have_received(:post_json)
  end
end
