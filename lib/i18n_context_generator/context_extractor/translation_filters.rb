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
        @android_resource_indexes_by_file = {}
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

        members_by_location = locations.to_h do |location|
          line_number = location.rpartition(':').last.to_i
          member = if metadata[:line_span]&.cover?(line_number)
                     entry.key
                   else
                     android_collection_member_at(location, translation_key_for(entry))
                   end
          [location, member]
        end
        return locations if members_by_location.values.compact.empty?

        locations.select { |location| members_by_location[location] == entry.key }
      end

      def android_collection_member_at(location, expected_parent)
        cache_key = [expected_parent, location]
        return @android_collection_members_by_location[cache_key] if @android_collection_members_by_location&.key?(cache_key)

        match = location.match(/\A(.+):(\d+)\z/)
        return unless match

        file = match[1]
        target_line = match[2].to_i
        member = scan_android_collection_members(file, target_line, expected_parent) if File.file?(file)
        @android_collection_members_by_location ||= {}
        @android_collection_members_by_location[cache_key] = member
      end

      def scan_android_collection_members(file, target_line, expected_parent)
        android_resource_index(file).member_at(target_line, parent: expected_parent)
      end

      def android_resource_index(file)
        @android_resource_indexes_by_file ||= {}
        @android_resource_indexes_by_file[file] ||=
          AndroidResource.index(File.read(file, encoding: 'UTF-8'))
      end

      def git_diff
        @git_diff ||= GitDiff.new(base_ref: @config.diff_base, head_ref: @config.diff_head)
      end
    end
  end
end
