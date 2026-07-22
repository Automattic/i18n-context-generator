# frozen_string_literal: true

module I18nContextGenerator
  module Parsers
    # Parses flat or nested JSON translation files into TranslationEntry objects.
    class JsonParser < Base
      def parse(path)
        data = Oj.load_file(path)
        raise Error, "Invalid JSON translation file #{path}: root must be an object" unless data.is_a?(Hash)

        flatten_keys(data).filter_map do |key, text|
          next if text.nil? || text.to_s.strip.empty?

          TranslationEntry.new(
            key: key,
            text: text.to_s,
            source_file: path
          )
        end
      rescue Oj::ParseError => e
        raise Error, "Failed to parse JSON translation file #{path}: #{e.message}"
      end
    end
  end
end
