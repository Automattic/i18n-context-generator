# frozen_string_literal: true

module I18nContextGenerator
  module LLM
    # OpenAI Responses API implementation of the LLM client.
    class OpenAI < Client
      API_URL = 'https://api.openai.com/v1/responses'
      DEFAULT_MODEL = 'gpt-5-mini'

      def initialize(api_url: API_URL, api_key: ENV.fetch('OPENAI_API_KEY', nil), require_api_key: true)
        super()
        @api_key = api_key
        raise Error, 'OPENAI_API_KEY environment variable is required' if require_api_key && !@api_key

        @uri = URI(api_url)
      end

      def generate_context(key:, text:, matches:, model: nil, comment: nil,
                           include_file_paths: false, redact_prompts: true,
                           max_prompt_chars: nil)
        outcome = nil
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
        outcome = request_with_retries(uri: @uri) { post_request(model: model, prompt: prompt) }
        handle_response(outcome.response, retries: outcome.retries)
      rescue PromptPreparationError => e
        ContextResult.new(description: 'Prompt preparation failed', error: e.message)
      rescue StandardError => e
        ContextResult.new(
          description: 'API request failed',
          error: e.message,
          **failure_request_telemetry(e, outcome: outcome)
        )
      end

      private

      def post_request(model:, prompt:)
        headers = {}
        headers['Authorization'] = "Bearer #{@api_key}" if @api_key
        post_json(
          uri: @uri,
          headers: headers,
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

      def handle_response(response, retries:)
        case response.code.to_i
        when 200
          body = JSON.parse(response.body)
          handle_successful_response(body, retries: retries)
        else
          http_error_result(response, retries: retries)
        end
      end

      def handle_successful_response(body, retries:)
        telemetry = usage_telemetry(body, retries: retries)
        status = body['status']
        return incomplete_result(body, telemetry: telemetry) if status == 'incomplete'
        return failed_result(body, telemetry: telemetry) if status == 'failed'

        unless status == 'completed'
          return ContextResult.new(
            description: 'Incomplete response',
            error: "Unexpected OpenAI response status: #{status || 'missing'}",
            **telemetry
          )
        end

        refusal = extract_refusal(body)
        if refusal
          return ContextResult.new(
            description: 'Provider refused request',
            error: "OpenAI refusal: #{refusal[0, 300]}",
            **telemetry
          )
        end

        parse_response(extract_output_text(body), telemetry: telemetry)
      end

      def incomplete_result(body, telemetry:)
        reason = body.dig('incomplete_details', 'reason') || 'unknown reason'
        ContextResult.new(
          description: 'Incomplete response',
          error: "OpenAI response incomplete: #{reason}",
          **telemetry
        )
      end

      def failed_result(body, telemetry:)
        message = body.dig('error', 'message') || 'unknown provider error'
        ContextResult.new(
          description: 'API error',
          error: "OpenAI response failed: #{message.to_s[0, 300]}",
          **telemetry
        )
      end

      def extract_refusal(body)
        Array(body['output']).each do |output_item|
          Array(output_item['content']).each do |content_item|
            next unless content_item['type'] == 'refusal'

            refusal = content_item['refusal'].to_s
            return refusal unless refusal.empty?
          end
        end
        nil
      end

      def extract_output_text(body)
        output_item = Array(body['output']).find { |item| item['type'] == 'message' }
        content_item = Array(output_item&.[]('content')).find { |item| item['type'] == 'output_text' }
        content_item&.dig('text')
      end

      def usage_telemetry(body, retries:)
        {
          input_tokens: body.dig('usage', 'input_tokens').to_i,
          output_tokens: body.dig('usage', 'output_tokens').to_i,
          retries: retries,
          request_count: retries + 1
        }
      end
    end
  end
end
