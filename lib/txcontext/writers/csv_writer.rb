# frozen_string_literal: true

module Txcontext
  module Writers
    class CsvWriter
      HEADERS = %w[key text description ui_element tone max_length locations error].freeze

      def write(results, path)
        CSV.open(path, "w") do |csv|
          csv << HEADERS

          results.sort_by(&:key).each do |result|
            csv << [
              result.key,
              result.text,
              result.description,
              result.ui_element,
              result.tone,
              result.max_length,
              result.locations.join(";"),
              result.error
            ]
          end
        end
      end
    end
  end
end
