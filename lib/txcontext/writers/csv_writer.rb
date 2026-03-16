# frozen_string_literal: true

module Txcontext
  module Writers
    # Writes extraction results to a CSV file.
    class CsvWriter
      HEADERS = %w[key text description ui_element tone max_length locations error].freeze
      DANGEROUS_CSV_PREFIX = /\A[ \t\r\n]*[=+\-@]/

      def write(results, path)
        CSV.open(path, 'w') do |csv|
          csv << HEADERS

          results.sort_by(&:key).each do |result|
            csv << [
              sanitize_cell(result.key),
              sanitize_cell(result.text),
              sanitize_cell(result.description),
              sanitize_cell(result.ui_element),
              sanitize_cell(result.tone),
              result.max_length,
              sanitize_cell(result.locations.join(';')),
              sanitize_cell(result.error)
            ]
          end
        end
      end

      private

      def sanitize_cell(value)
        return value unless value.is_a?(String)
        return value unless value.match?(DANGEROUS_CSV_PREFIX)

        "'#{value}"
      end
    end
  end
end
