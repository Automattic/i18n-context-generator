# frozen_string_literal: true

module I18nContextGenerator
  module Writers
    # Writes extraction results to a CSV file.
    class CsvWriter
      HEADERS = %w[
        key text description ui_element tone max_length confidence
        ambiguity_reason locations status cache_hit request_count input_tokens
        output_tokens retries error
      ].freeze
      DANGEROUS_CSV_PREFIX = /\A[ \t\r\n]*[=+\-@]/

      def write(results, path, **_options)
        return write_rows(CSV.new($stdout), results) if path == '-'

        CSV.open(path, 'w') { |csv| write_rows(csv, results) }
      end

      private

      def write_rows(csv, results)
        csv << HEADERS

        results.sort_by(&:key).each do |result|
          csv << [
            sanitize_cell(result.key),
            sanitize_cell(result.text),
            sanitize_cell(result.description),
            sanitize_cell(result.ui_element),
            sanitize_cell(result.tone),
            result.max_length,
            sanitize_cell(result.confidence),
            sanitize_cell(result.ambiguity_reason),
            sanitize_cell(result.locations.join(';')),
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
