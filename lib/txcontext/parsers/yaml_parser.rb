# frozen_string_literal: true

module Txcontext
  module Parsers
    class YamlParser < Base
      def parse(path)
        data = YAML.load_file(path)

        # Skip top-level locale key if present (Rails i18n style)
        # e.g., { "en" => { "hello" => "Hello" } } -> { "hello" => "Hello" }
        if data.is_a?(Hash) && data.keys.size == 1 && data.values.first.is_a?(Hash)
          locale_key = data.keys.first
          # Only skip if it looks like a locale code (2-5 chars)
          data = data.values.first if locale_key.match?(/\A[a-z]{2}(-[A-Z]{2})?\z/i)
        end

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
