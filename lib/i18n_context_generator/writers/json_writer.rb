# frozen_string_literal: true

require 'time'

module I18nContextGenerator
  module Writers
    # Writes extraction results to a JSON file.
    class JsonWriter
      include ResultSerialization

      def write(results, path, metrics: nil, output: $stdout)
        document = {
          schema_version: OUTPUT_SCHEMA_VERSION,
          generated_at: Time.now.iso8601,
          version: I18nContextGenerator::VERSION,
          total: results.size,
          metrics: metrics&.to_h,
          entries: results.sort_by { |result| result_sort_key(result) }.map do |result|
            {
              key: result.key,
              source_file: result.source_file,
              translation_key: result.translation_key,
              text: result.text,
              context: {
                description: result.description,
                ui_element: result.ui_element,
                tone: result.tone,
                max_length: result.max_length,
                confidence: result.confidence,
                ambiguity_reason: result.ambiguity_reason
              },
              locations: serialize_locations(result.locations),
              changed_locations: serialize_locations(result.changed_locations),
              changed_location_groups: serialize_location_groups(result.changed_location_groups),
              changed_translation_locations: serialize_locations(result.changed_translation_locations),
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

        rendered = Oj.dump(document, indent: 2, mode: :compat)
        if path == '-'
          output.write(rendered)
          output.write("\n") unless rendered.end_with?("\n")
        else
          File.write(path, rendered)
        end
      end
    end
  end
end
