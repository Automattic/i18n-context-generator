# frozen_string_literal: true

module Txcontext
  module LLM
    class Anthropic < Client
      API_URL = "https://api.anthropic.com/v1/messages"
      DEFAULT_MODEL = "claude-sonnet-4-20250514"

      def initialize
        @api_key = ENV["ANTHROPIC_API_KEY"]
        raise Error, "ANTHROPIC_API_KEY environment variable is required" unless @api_key

        @http = HTTPX.with(
          headers: {
            "x-api-key" => @api_key,
            "anthropic-version" => "2023-06-01",
            "content-type" => "application/json"
          },
          timeout: { operation_timeout: 60 }
        )
      end

      def generate_context(key:, text:, matches:, model: nil)
        model ||= DEFAULT_MODEL
        prompt = build_prompt(key: key, text: text, matches: matches)

        response = @http.post(API_URL, json: {
          model: model,
          max_tokens: 500,
          messages: [{ role: "user", content: prompt }]
        })

        handle_response(response)
      rescue HTTPX::Error => e
        ContextResult.new(description: "API request failed", error: e.message)
      end

      private

      def handle_response(response)
        case response.status
        when 200
          body = Oj.load(response.body.to_s)
          content = body.dig("content", 0, "text")
          parse_response(content)
        when 429
          ContextResult.new(description: "Rate limited", error: "Rate limit exceeded - try reducing concurrency")
        when 401
          ContextResult.new(description: "Authentication failed", error: "Invalid API key")
        else
          error_body = Oj.load(response.body.to_s) rescue {}
          error_msg = error_body.dig("error", "message") || "HTTP #{response.status}"
          ContextResult.new(description: "API error", error: error_msg)
        end
      end
    end
  end
end
