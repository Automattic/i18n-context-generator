# frozen_string_literal: true

module I18nContextGenerator
  module Writers
    # Writes extraction results to a CSV file.
    class CsvWriter
      include ResultSerialization

      HEADERS = %w[
        schema_version key source_file translation_key text description ui_element
        tone max_length confidence ambiguity_reason locations changed_locations
        changed_location_groups changed_translation_locations status cache_hit
        request_count input_tokens output_tokens retries error
      ].freeze
      DANGEROUS_CSV_PREFIX = /\A[ \t\r\n]*[=+\-@]/

      def write(results, path, output: $stdout, **_options)
        return write_rows(CSV.new(output), results) if path == '-'

        CSV.open(path, 'w') { |csv| write_rows(csv, results) }
      end

      private

      def write_rows(csv, results)
        csv << HEADERS

        results.sort_by { |result| result_sort_key(result) }.each do |result|
          csv << [
            OUTPUT_SCHEMA_VERSION,
            sanitize_cell(result.key),
            sanitize_cell(result.source_file),
            sanitize_cell(result.translation_key),
            sanitize_cell(result.text),
            sanitize_cell(result.description),
            sanitize_cell(result.ui_element),
            sanitize_cell(result.tone),
            result.max_length,
            sanitize_cell(result.confidence),
            sanitize_cell(result.ambiguity_reason),
            sanitize_cell(Oj.dump(serialize_locations(result.locations), mode: :compat)),
            sanitize_cell(Oj.dump(serialize_locations(result.changed_locations), mode: :compat)),
            sanitize_cell(Oj.dump(serialize_location_groups(result.changed_location_groups), mode: :compat)),
            sanitize_cell(Oj.dump(serialize_locations(result.changed_translation_locations), mode: :compat)),
            result.status,
            result.cache_hit,
            result.request_count,
            result.input_tokens,
            result.output_tokens,
            result.retries,
            sanitize_cell(result.error)
          ]
        end
      end

      def sanitize_cell(value)
        return value unless value.is_a?(String)
        return value unless value.match?(DANGEROUS_CSV_PREFIX)

        "'#{value}"
      end
    end
  end
end
