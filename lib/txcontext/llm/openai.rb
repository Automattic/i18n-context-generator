# frozen_string_literal: true

module Txcontext
  module LLM
    # OpenAI Responses API implementation of the LLM client.
    class OpenAI < Client
      API_URL = 'https://api.openai.com/v1/responses'
      DEFAULT_MODEL = 'gpt-5-mini'
      MAX_RETRIES = 2
      RESPONSE_SCHEMA = {
        type: 'object',
        additionalProperties: false,
        required: %w[description ui_element tone max_length],
        properties: {
          description: { type: 'string' },
          ui_element: { type: %w[string null], enum: %w[button label title alert toast placeholder navigation menu tab error confirmation other] + [nil] },
          tone: { type: %w[string null], enum: %w[formal casual urgent friendly technical neutral] + [nil] },
          max_length: { type: %w[integer null] }
        }
      }.freeze

      def initialize
        super
        @api_key = ENV.fetch('OPENAI_API_KEY', nil)
        raise Error, 'OPENAI_API_KEY environment variable is required' unless @api_key

        @uri = URI(API_URL)
      end

      def generate_context(key:, text:, matches:, model: nil, comment: nil,
                           include_file_paths: false, redact_prompts: true)
        model ||= DEFAULT_MODEL
        prompt = build_prompt(
          key: key,
          text: text,
          matches: matches,
          comment: comment,
          include_file_paths: include_file_paths,
          redact_prompts: redact_prompts
        )
        retries = 0

        loop do
          response = post_request(model: model, prompt: prompt)

          if response.code.to_i == 429 && retries < MAX_RETRIES
            retries += 1
            delay = (response['retry-after']&.to_i || 2) * retries
            sleep(delay)
            next
          end

          return handle_response(response)
        end
      rescue StandardError => e
        ContextResult.new(description: 'API request failed', error: e.message)
      end

      private

      def post_request(model:, prompt:)
        post_json(
          uri: @uri,
          headers: {
            'Authorization' => "Bearer #{@api_key}"
          },
          body: {
            model: model,
            store: false,
            instructions: SYSTEM_PROMPT,
            input: prompt,
            max_output_tokens: 500,
            text: {
              format: {
                type: 'json_schema',
                name: 'translation_context',
                strict: true,
                schema: RESPONSE_SCHEMA
              }
            }
          }
        )
      end

      def handle_response(response)
        case response.code.to_i
        when 200
          body = JSON.parse(response.body)
          parse_response(extract_output_text(body))
        when 429
          ContextResult.new(description: 'Rate limited', error: 'Rate limit exceeded - try reducing concurrency')
        when 401
          ContextResult.new(description: 'Authentication failed', error: 'Invalid API key')
        else
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end
          error_msg = error_body.dig('error', 'message') || error_body['message'] || "HTTP #{response.code}"
          ContextResult.new(description: 'API error', error: error_msg)
        end
      end

      def extract_output_text(body)
        output_item = Array(body['output']).find { |item| item['type'] == 'message' }
        content_item = Array(output_item&.[]('content')).find { |item| item['type'] == 'output_text' }
        content_item&.dig('text')
      end
    end
  end
end
