# frozen_string_literal: true

module I18nContextGenerator
  module LLM
    # Claude API implementation of the LLM client.
    class Anthropic < Client
      API_URL = 'https://api.anthropic.com/v1/messages'
      ANTHROPIC_VERSION = '2023-06-01'
      DEFAULT_MODEL = 'claude-sonnet-4-6'

      def initialize
        super
        @api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
        raise Error, 'ANTHROPIC_API_KEY environment variable is required' unless @api_key

        @uri = URI(API_URL)
      end

      def generate_context(key:, text:, matches:, model: nil, comment: nil,
                           include_file_paths: false, redact_prompts: true,
                           max_prompt_chars: nil)
        model = resolved_model(model)
        prompt = build_prompt(
          key: key,
          text: text,
          matches: matches,
          comment: comment,
          include_file_paths: include_file_paths,
          redact_prompts: redact_prompts,
          max_prompt_chars: max_prompt_chars
        )
        response = request_with_retries(uri: @uri) { post_request(model: model, prompt: prompt) }
        handle_response(response)
      rescue PromptPreparationError => e
        ContextResult.new(description: 'Prompt preparation failed', error: e.message)
      rescue StandardError => e
        ContextResult.new(description: 'API request failed', error: e.message)
      end

      private

      def post_request(model:, prompt:)
        post_json(
          uri: @uri,
          headers: {
            'anthropic-version' => ANTHROPIC_VERSION,
            'x-api-key' => @api_key
          },
          body: {
            model: model,
            max_tokens: 500,
            system: SYSTEM_PROMPT,
            messages: [{ role: 'user', content: prompt }],
            output_config: {
              format: {
                type: 'json_schema',
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
          handle_successful_response(body)
        else
          http_error_result(response)
        end
      end

      def handle_successful_response(body)
        case body['stop_reason']
        when 'end_turn'
          content = Array(body['content']).find { |item| item['type'] == 'text' }
          parse_response(content&.[]('text'))
        when 'refusal'
          ContextResult.new(description: 'Provider refused request', error: 'Anthropic refused to generate context')
        when 'max_tokens'
          ContextResult.new(description: 'Incomplete response', error: 'Anthropic response reached max_tokens')
        else
          reason = body['stop_reason'] || 'missing'
          ContextResult.new(description: 'Incomplete response', error: "Unexpected Anthropic stop reason: #{reason}")
        end
      end
    end
  end
end
