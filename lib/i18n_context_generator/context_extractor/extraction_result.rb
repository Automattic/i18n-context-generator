# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Result for a single translation key, including evidence, review state, and
    # run-local provider/cache telemetry.
    ExtractionResult = Data.define(
      :key, :text, :description, :source_file, :ui_element, :tone, :max_length,
      :locations, :changed_locations, :translation_key, :changed_location_groups,
      :changed_translation_locations, :confidence, :ambiguity_reason, :cache_hit,
      :request_count, :input_tokens, :output_tokens, :retries, :status, :error
    ) do
      def initialize(key:, text:, description:, **attributes)
        defaults = {
          source_file: nil,
          ui_element: nil,
          tone: nil,
          max_length: nil,
          locations: [],
          changed_locations: [],
          changed_location_groups: [],
          translation_key: key,
          changed_translation_locations: [],
          confidence: nil,
          ambiguity_reason: nil,
          cache_hit: false,
          request_count: 0,
          input_tokens: 0,
          output_tokens: 0,
          retries: 0,
          status: attributes[:error] ? :error : :success,
          error: nil
        }
        values = defaults.merge(attributes)
        values[:status] = values[:status].to_sym if values[:status].respond_to?(:to_sym)
        super(key: key, text: text, description: description, **values)
      end

      def actionable? = status == :success && error.nil? && !description.to_s.strip.empty?

      def to_h
        members.to_h { |member| [member, public_send(member)] }
      end
    end
  end
end
