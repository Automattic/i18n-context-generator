# frozen_string_literal: true

module Txcontext
  module Parsers
    class JsonParser < Base
      def parse(path)
        data = Oj.load_file(path)
        flatten_keys(data).filter_map do |key, text|
          next if text.nil? || text.to_s.strip.empty?

          TranslationEntry.new(
            key: key,
            text: text.to_s,
            source_file: path
          )
        end
      end
    end
  end
end
