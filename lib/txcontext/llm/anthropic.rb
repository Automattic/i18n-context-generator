# frozen_string_literal: true

module Txcontext
  module LLM
    # Claude API implementation of the LLM client with retry logic for rate limits.
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

      MAX_RETRIES = 2

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

          # Retry on rate limit with backoff
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
            'anthropic-version' => ANTHROPIC_VERSION,
            'x-api-key' => @api_key
          },
          body: {
            model: model,
            max_tokens: 500,
            system: SYSTEM_PROMPT,
            messages: [{ role: 'user', content: prompt }]
          }
        )
      end

      def handle_response(response)
        case response.code.to_i
        when 200
          body = JSON.parse(response.body)
          content = body.dig('content', 0, 'text')
          parse_response(content)
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
          error_msg = error_body.dig('error', 'message') || "HTTP #{response.code}"
          ContextResult.new(description: 'API error', error: error_msg)
        end
      end
    end
  end
end
