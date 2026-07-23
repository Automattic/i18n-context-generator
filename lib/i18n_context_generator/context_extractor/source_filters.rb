# frozen_string_literal: true

require 'pathname'

module I18nContextGenerator
  class ContextExtractor
    # Helpers for filtering source-discovered entries without narrowing the full
    # source search scope used later for context lookup.
    module SourceFilters
      private

      def source_discovery?
        !translation_backed_discovery?
      end

      def source_discovery_filtered_by_diff?
        source_discovery? && @config.diff_base && @config.source_line_filter.nil?
      end

      def filter_source_entries(entries)
        line_filter = source_line_filter
        return entries if line_filter.nil?
        return [] if line_filter.empty?

        entries.select do |entry|
          entry.locations.any? do |location|
            changed_location?(location, line_filter)
          end
        end
      end

      def source_line_filter
        return @source_line_filter if defined?(@source_line_filter)

        @source_line_filter =
          if @config.source_line_filter
            normalize_source_line_filter(@config.source_line_filter)
          elsif @config.diff_base
            git_diff.changed_lines(@config.source_paths)
          end
      end

      def changed_result_locations_for(locations)
        line_filter = source_line_filter
        return [] unless line_filter

        locations.select do |location|
          changed_location?(location, line_filter)
        end
      end

      def changed_result_location_groups_for(entry, changed_locations)
        return [] if changed_locations.empty?

        location_groups = entry.metadata&.dig(:source_location_groups)
        return changed_locations.map { |location| [location] } unless location_groups&.any?

        changed_location_set = changed_locations.to_set
        location_groups.filter_map do |group|
          changed_group = Array(group).select { |location| changed_location_set.include?(location) }
          changed_group unless changed_group.empty?
        end
      end

      def changed_location_attributes_for(entry, locations)
        changed_locations = changed_result_locations_for(locations)
        {
          changed_locations: changed_locations,
          changed_location_groups: changed_result_location_groups_for(entry, changed_locations)
        }
      end

      def normalize_source_line_filter(filter)
        filter.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |(file, lines), normalized_filter|
          next if file.nil?

          normalized_lines = Array(lines).filter_map { |line| Integer(line, exception: false) }
          next if normalized_lines.empty?

          normalized_filter[normalize_source_file(file)].merge(normalized_lines)
        end
      end

      def changed_location?(location, line_filter)
        file, _, line = location.rpartition(':')
        line_filter.fetch(normalize_source_file(file), Set.new).include?(line.to_i)
      end

      def normalize_source_file(file)
        Pathname.new(file.to_s).cleanpath.to_s
      end

      def result_locations_for(entry, matches)
        source_locations = entry.metadata&.dig(:source_locations)
        return source_locations if source_locations&.any?

        source_location = entry.metadata&.dig(:source_location)
        return Array(source_location) if source_location

        matches.map { |m| "#{m.file}:#{m.line}" }
      end
    end
  end
end
