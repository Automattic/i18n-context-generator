# frozen_string_literal: true

module I18nContextGenerator
  module Parsers
    # Parser for Apple string catalogs. Context generation is keyed by the
    # catalog entry rather than by individual target-language localizations.
    class XcstringsParser < Base
      def parse(path)
        catalog = load_catalog(path)
        source_language = catalog['sourceLanguage']

        catalog.fetch('strings').filter_map do |key, entry|
          next if key.empty?
          next if entry['shouldTranslate'] == false

          TranslationEntry.new(
            key: key,
            text: source_text(key, entry, source_language),
            source_file: path,
            metadata: {
              comment: entry['comment'],
              source_language: source_language,
              resource_type: :string
            }.compact
          )
        end
      rescue KeyError => e
        raise Error, "Failed to parse Apple string catalog #{path}: missing #{e.key.inspect}"
      rescue Oj::ParseError, TypeError => e
        raise Error, "Failed to parse Apple string catalog #{path}: #{e.message}"
      end

      def self.validate_catalog!(catalog, path:)
        raise TypeError, 'root must be a mapping' unless catalog.is_a?(Hash)
        raise TypeError, 'sourceLanguage must be a non-empty string' unless nonempty_string?(catalog['sourceLanguage'])
        raise TypeError, 'strings must be a mapping' unless catalog['strings'].is_a?(Hash)

        valid_entries = catalog['strings'].all? { |key, entry| key.is_a?(String) && entry.is_a?(Hash) }
        raise TypeError, 'strings must map string keys to entries' unless valid_entries

        catalog
      rescue TypeError => e
        raise Error, "Failed to parse Apple string catalog #{path}: #{e.message}"
      end

      def self.nonempty_string?(value)
        value.is_a?(String) && !value.empty?
      end
      private_class_method :nonempty_string?

      private

      def load_catalog(path)
        catalog = Oj.load_file(path, mode: :strict)
        self.class.validate_catalog!(catalog, path: path)
      end

      def source_text(key, entry, source_language)
        localization = entry.dig('localizations', source_language)
        values = string_unit_values(localization)
        values.empty? ? key : values.join(' | ')
      end

      def string_unit_values(value)
        case value
        when Hash
          direct_value = value.dig('stringUnit', 'value')
          return [direct_value] if direct_value.is_a?(String)

          value.values.flat_map { |child| string_unit_values(child) }
        when Array
          value.flat_map { |child| string_unit_values(child) }
        else
          []
        end
      end
    end
  end
end
