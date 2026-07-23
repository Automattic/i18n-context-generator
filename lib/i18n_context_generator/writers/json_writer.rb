# frozen_string_literal: true

require 'time'

module I18nContextGenerator
  module Writers
    # Writes extraction results to a JSON file.
    class JsonWriter
      def write(results, path, metrics: nil)
        output = {
          generated_at: Time.now.iso8601,
          version: I18nContextGenerator::VERSION,
          total: results.size,
          metrics: metrics&.to_h,
          entries: results.sort_by(&:key).map do |result|
            {
              key: result.key,
              text: result.text,
              context: {
                description: result.description,
                ui_element: result.ui_element,
                tone: result.tone,
                max_length: result.max_length,
                confidence: result.confidence,
                ambiguity_reason: result.ambiguity_reason
              },
              locations: result.locations,
              status: result.status,
              telemetry: {
                cache_hit: result.cache_hit,
                request_count: result.request_count,
                input_tokens: result.input_tokens,
                output_tokens: result.output_tokens,
                retries: result.retries
              },
              error: result.error
            }
          end
        }

        rendered = Oj.dump(output, indent: 2, mode: :compat)
        if path == '-'
          $stdout.write(rendered)
          $stdout.write("\n") unless rendered.end_with?("\n")
        else
          File.write(path, rendered)
        end
      end
    end
  end
end
