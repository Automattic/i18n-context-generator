# frozen_string_literal: true

module Txcontext
  module LLM
    # Claude API implementation of the LLM client with retry logic for rate limits.
    class Anthropic < Client
      API_URL = 'https://api.anthropic.com/v1/messages'
      DEFAULT_MODEL = 'claude-sonnet-4-6-20250610'

      def initialize
        super
        @api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
        raise Error, 'ANTHROPIC_API_KEY environment variable is required' unless @api_key

        @http = HTTPX.with(
          headers: {
            'x-api-key' => @api_key,
            'anthropic-version' => '2023-06-01',
            'content-type' => 'application/json'
          },
          timeout: { operation_timeout: 60 }
        )
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
          response = @http.post(API_URL, json: {
                                  model: model,
                                  max_tokens: 500,
                                  system: 'You are a mobile app localization expert. Analyze code usage and provide concise, specific context for translators. Respond with only valid JSON.',
                                  messages: [{ role: 'user', content: prompt }]
                                })

          # Retry on rate limit with backoff
          if response.status == 429 && retries < MAX_RETRIES
            retries += 1
            delay = (response.headers['retry-after']&.to_i || 2) * retries
            sleep(delay)
            next
          end

          return handle_response(response)
        end
      rescue HTTPX::Error => e
        ContextResult.new(description: 'API request failed', error: e.message)
      end

      private

      def handle_response(response)
        case response.status
        when 200
          body = Oj.load(response.body.to_s)
          content = body.dig('content', 0, 'text')
          parse_response(content)
        when 429
          ContextResult.new(description: 'Rate limited', error: 'Rate limit exceeded - try reducing concurrency')
        when 401
          ContextResult.new(description: 'Authentication failed', error: 'Invalid API key')
        else
          error_body = begin
            Oj.load(response.body.to_s)
          rescue StandardError
            {}
          end
          error_msg = error_body.dig('error', 'message') || "HTTP #{response.status}"
          ContextResult.new(description: 'API error', error: error_msg)
        end
      end
    end
  end
end
