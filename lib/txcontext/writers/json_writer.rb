# frozen_string_literal: true

module Txcontext
  module Writers
    class JsonWriter
      def write(results, path)
        output = {
          generated_at: Time.now.iso8601,
          version: Txcontext::VERSION,
          total: results.size,
          entries: results.sort_by(&:key).map do |result|
            {
              key: result.key,
              text: result.text,
              context: {
                description: result.description,
                ui_element: result.ui_element,
                tone: result.tone,
                max_length: result.max_length
              },
              locations: result.locations,
              error: result.error
            }
          end
        }

        File.write(path, Oj.dump(output, indent: 2, mode: :compat))
      end
    end
  end
end
