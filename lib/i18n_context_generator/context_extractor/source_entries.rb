# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Loads source-discovered entries and hydrates them from translation files.
    module SourceEntries
      private

      def load_entries
        case normalized_discovery_mode
        when 'source'
          load_source_entries
        when 'translations'
          load_translations
        else
          auto_discovery_entries
        end
      end

      def auto_discovery_entries
        return load_source_entries if @config.translations.empty?

        load_translations
      end

      def load_source_entries
        discovered_entries = filter_source_entries(searcher.discover_localization_entries)

        discovered_entries.flat_map do |entry|
          hydrated_entries = translation_entries_for_discovered(entry)
          hydrated_entries = [nil] if hydrated_entries.empty?

          hydrated_entries.map { |hydrated_entry| build_source_entry(entry, hydrated_entry) }
        end
      end

      def build_source_entry(entry, hydrated_entry)
        translation_comment = hydrated_entry&.metadata&.dig(:comment)
        source_comment = entry.comment
        metadata = hydrated_entry&.metadata&.dup || {}
        metadata[:comment] = translation_comment || source_comment if translation_comment || source_comment
        metadata[:source_location] = "#{entry.file}:#{entry.line}"
        metadata[:source_locations] = entry.locations
        metadata[:resource_type] = entry.resource_type unless entry.resource_type == :string

        Parsers::TranslationEntry.new(
          key: hydrated_entry&.key || entry.key,
          text: hydrated_entry&.text || entry.text || entry.key,
          source_file: hydrated_entry&.source_file,
          metadata: metadata
        )
      end

      def load_translation_lookup
        return @load_translation_lookup if defined?(@load_translation_lookup)

        empty_lookup = Hash.new { |hash, key| hash[key] = [] }
        @load_translation_lookup = load_translations.each_with_object(empty_lookup) do |entry, lookup|
          lookup[entry.key] << entry
        end
      end

      def load_translation_resource_lookup
        return @load_translation_resource_lookup if defined?(@load_translation_resource_lookup)

        empty_lookup = Hash.new { |hash, key| hash[key] = [] }
        @load_translation_resource_lookup = load_translations.each_with_object(empty_lookup) do |entry, lookup|
          metadata = entry.metadata || {}
          if metadata[:plural]
            lookup[[:plural, metadata[:plural]]] << entry
          elsif metadata[:array]
            lookup[[:array, metadata[:array]]] << entry
          end
        end
      end

      def translation_entries_for_discovered(entry)
        case entry.resource_type
        when :plural, :array
          load_translation_resource_lookup[[entry.resource_type, entry.key]]
        else
          load_translation_lookup[entry.key]
        end
      end

      def normalized_discovery_mode
        @config.discovery_mode.to_s.downcase
      end

      def translation_backed_discovery?
        return true if normalized_discovery_mode == 'translations'
        return false if normalized_discovery_mode == 'source'

        @config.translations.any?
      end

      def entry_label_for_logging
        translation_backed_discovery? ? 'translation keys' : 'source localization entries'
      end
    end
  end
end
