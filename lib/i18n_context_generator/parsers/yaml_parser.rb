# frozen_string_literal: true

module I18nContextGenerator
  module Parsers
    # Parses YAML translation files (including Rails i18n style) into TranslationEntry objects.
    class YamlParser < Base
      def initialize(locale: nil)
        super()
        @locale = locale
      end

      def parse(path)
        data = YAML.safe_load_file(path, permitted_classes: [])
        raise Error, "Invalid YAML translation file #{path}: root must be a mapping" unless data.is_a?(Hash)

        data = locale_root(data, path) if @locale

        flatten_keys(data).filter_map do |key, text|
          next if text.nil? || text.to_s.strip.empty?

          TranslationEntry.new(
            key: key,
            text: text.to_s,
            source_file: path
          )
        end
      rescue Psych::SyntaxError => e
        raise Error, "Failed to parse YAML translation file #{path}: #{e.problem} at line #{e.line}, column #{e.column}"
      rescue Psych::Exception => e
        raise Error, "Failed to parse YAML translation file #{path}: #{e.message}"
      end

      private

      def locale_root(data, path)
        root = data[@locale]
        raise Error, "YAML translation file #{path} does not contain locale root #{@locale.inspect}" unless root.is_a?(Hash)

        root
      end
    end
  end
end
