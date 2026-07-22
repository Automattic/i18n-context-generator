# frozen_string_literal: true

require 'pathname'
require_relative '../android_resource'

module I18nContextGenerator
  class ContextExtractor
    # Filters translation-backed entries and retains their changed inline locations.
    module TranslationFilters
      private

      def filter_by_diff(entries)
        @android_collection_members_by_location = {}
        @changed_translation_locations = git_diff.changed_key_locations(@config.translations)

        return [] if @changed_translation_locations.empty?

        puts "Found #{@changed_translation_locations.size} changed translation entries in git diff"

        entries.select { |entry| changed_translation_locations_for(entry).any? }
      end

      # Extract the base resource name from composite Android keys.
      def android_base_key(key)
        AndroidResource.base_key(key)
      end

      def translation_key_for(entry)
        metadata = entry.metadata || {}
        metadata[:plural] || metadata[:array] || android_base_key(entry.key)
      end

      def changed_translation_locations_for(entry)
        return [] unless @changed_translation_locations
        return [] unless entry.source_file

        source_file = Pathname.new(entry.source_file).cleanpath.to_s
        locations = @changed_translation_locations.fetch([source_file, translation_key_for(entry)], [])
        narrow_android_collection_locations(entry, locations)
      end

      def narrow_android_collection_locations(entry, locations)
        metadata = entry.metadata || {}
        return locations unless metadata[:plural] || metadata[:array]

        locations.select do |location|
          line_number = location.rpartition(':').last.to_i
          next true if metadata[:line_span]&.cover?(line_number)

          member = android_collection_member_at(location, translation_key_for(entry))
          member.nil? || member == entry.key
        end
      end

      def android_collection_member_at(location, expected_parent)
        cache_key = [expected_parent, location]
        return @android_collection_members_by_location[cache_key] if @android_collection_members_by_location&.key?(cache_key)

        match = location.match(/\A(.+):(\d+)\z/)
        member = if match
                   file = match[1]
                   target_line = match[2].to_i
                   scan_android_collection_members(file, target_line, expected_parent) if File.file?(file)
                 end

        @android_collection_members_by_location ||= {}
        @android_collection_members_by_location[cache_key] = member
      end

      def scan_android_collection_members(file, target_line, expected_parent)
        content = File.read(file, encoding: 'UTF-8')
        AndroidResource.index(content).member_at(target_line, parent: expected_parent)
      end

      def git_diff
        @git_diff ||= GitDiff.new(base_ref: @config.diff_base, head_ref: @config.diff_head)
      end
    end
  end
end
