# frozen_string_literal: true

module I18nContextGenerator
  module LLM
    # Explicit OpenAI Responses-compatible endpoint support. A separate
    # credential variable prevents local or third-party endpoints from ever
    # receiving the official OpenAI credential by accident.
    class OpenAICompatible < OpenAI
      DEFAULT_MODEL = nil

      def initialize(endpoint:)
        super(
          api_url: endpoint,
          api_key: ENV.fetch('OPENAI_COMPATIBLE_API_KEY', nil),
          require_api_key: false
        )
      end
    end
  end
end
