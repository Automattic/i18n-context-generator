# frozen_string_literal: true

require 'pathname'

module I18nContextGenerator
  class ContextExtractor
    # Filters translation-backed entries and retains their changed inline locations.
    module TranslationFilters
      private

      def filter_by_diff(entries)
        @changed_translation_locations = git_diff.changed_key_locations(@config.translations)

        if @changed_translation_locations.empty?
          puts "No changes detected in translation files for #{@config.diff_base}...#{@config.diff_head}"
          return []
        end

        puts "Found #{@changed_translation_locations.size} changed translation entries in git diff"

        entries.select { |entry| changed_translation_locations_for(entry).any? }
      end

      # Extract the base resource name from composite Android keys.
      def android_base_key(key)
        key.sub(/:[a-z]+$/, '').sub(/\[\d+\]$/, '')
      end

      def translation_key_for(entry)
        metadata = entry.metadata || {}
        metadata[:plural] || metadata[:array] || android_base_key(entry.key)
      end

      def changed_translation_locations_for(entry)
        return [] unless @changed_translation_locations
        return [] unless entry.source_file

        source_file = Pathname.new(entry.source_file).cleanpath.to_s
        @changed_translation_locations.fetch([source_file, translation_key_for(entry)], [])
      end

      def git_diff
        @git_diff ||= GitDiff.new(base_ref: @config.diff_base, head_ref: @config.diff_head)
      end
    end
  end
end
