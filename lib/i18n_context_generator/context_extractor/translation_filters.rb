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
        locations = @changed_translation_locations.fetch([source_file, translation_key_for(entry)], [])
        narrow_android_collection_locations(entry, locations)
      end

      def narrow_android_collection_locations(entry, locations)
        metadata = entry.metadata || {}
        return locations unless metadata[:plural] || metadata[:array]

        members_by_location = locations.to_h do |location|
          [location, android_collection_member_at(location, translation_key_for(entry))]
        end
        return locations if members_by_location.values.compact.empty?

        locations.select { |location| members_by_location[location] == entry.key }
      end

      def android_collection_member_at(location, expected_parent)
        match = location.match(/\A(.+):(\d+)\z/)
        return unless match

        file = match[1]
        target_line = match[2].to_i
        return unless File.file?(file)

        scan_android_collection_members(file, target_line, expected_parent)
      end

      def scan_android_collection_members(file, target_line, expected_parent)
        state = android_collection_scan_state

        File.foreach(file).with_index(1) do |line, line_number|
          track_android_collection_parent(state, line)
          track_android_collection_item(state, line)
          member = state[:member] if state[:parent_name] == expected_parent
          return member if line_number == target_line

          close_android_collection_elements(state, line)
        end
        nil
      end

      def android_collection_scan_state
        {
          parent_name: nil,
          parent_type: nil,
          array_index: -1,
          member: nil,
          pending_parent: nil,
          pending_item: nil
        }
      end

      def track_android_collection_parent(state, line)
        if state[:pending_parent]
          state[:pending_parent] << line
        elsif (tag_start = line.index(/<(?:plurals|string-array)\b/))
          state[:pending_parent] = line[tag_start..]
        end
        return unless state[:pending_parent]&.include?('>')

        tag = state[:pending_parent]
        type = tag[/<(plurals|string-array)\b/, 1]
        name = tag[/\bname\s*=\s*(["'])(.*?)\1/m, 2]
        if type && name
          state[:parent_type] = type
          state[:parent_name] = name
          state[:array_index] = -1
        end
        state[:pending_parent] = nil
      end

      def track_android_collection_item(state, line)
        return unless state[:parent_name]

        if state[:pending_item]
          state[:pending_item] << line
        elsif (tag_start = line.index(/<item\b/))
          state[:pending_item] = line[tag_start..]
        end
        return unless state[:pending_item]&.include?('>')

        tag = state[:pending_item]
        if state[:parent_type] == 'plurals'
          quantity = tag[/\bquantity\s*=\s*(["'])(.*?)\1/m, 2]
          state[:member] = "#{state[:parent_name]}:#{quantity}" if quantity
        else
          state[:array_index] += 1
          state[:member] = "#{state[:parent_name]}[#{state[:array_index]}]"
        end
        state[:pending_item] = nil
      end

      def close_android_collection_elements(state, line)
        state[:member] = nil if line.include?('</item>') || line.match?(%r{<item\b[^>]*/>})
        return unless line.match?(%r{</(?:plurals|string-array)>})

        state[:parent_name] = nil
        state[:parent_type] = nil
        state[:member] = nil
      end

      def git_diff
        @git_diff ||= GitDiff.new(base_ref: @config.diff_base, head_ref: @config.diff_head)
      end
    end
  end
end
