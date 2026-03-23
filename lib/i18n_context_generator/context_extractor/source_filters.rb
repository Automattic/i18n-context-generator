# frozen_string_literal: true

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
          line_filter.fetch(entry.file.to_s, Set.new).include?(entry.line)
        end
      end

      def source_line_filter
        return @source_line_filter if defined?(@source_line_filter)

        @source_line_filter =
          if @config.source_line_filter
            normalize_source_line_filter(@config.source_line_filter)
          elsif @config.diff_base && source_discovery?
            GitDiff.new(base_ref: @config.diff_base).changed_lines(@config.source_paths)
          end
      end

      def normalize_source_line_filter(filter)
        filter.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |(file, lines), normalized_filter|
          next if file.nil?

          normalized_lines = Array(lines).filter_map { |line| Integer(line, exception: false) }
          next if normalized_lines.empty?

          normalized_filter[file.to_s].merge(normalized_lines)
        end
      end

      def result_locations_for(entry, matches)
        source_location = entry.metadata&.dig(:source_location)
        return [source_location] if source_location

        matches.map { |m| "#{m.file}:#{m.line}" }
      end
    end
  end
end
