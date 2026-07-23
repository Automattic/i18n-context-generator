# frozen_string_literal: true

module I18nContextGenerator
  class Searcher
    # Source-discovery helpers used for source-first extraction runs.
    module SourceDiscovery
      IOS_COMMENT_ARGUMENT_PATTERN = /\bcomment:\s*["'](?<comment>(?:\\.|[^"'\\])*)["']/

      def discover_localization_entries
        entries = discover_files.flat_map do |file|
          discover_entries_in_file(file)
        end

        deduplicate_discovered_entries(entries)
      end

      private

      def discover_entries_in_file(file)
        case platform_for_file(file)
        when :ios
          discover_ios_entries(file)
        when :android
          discover_android_entries(file)
        else
          []
        end
      rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR => e
        warn "Warning: Could not read #{file}: #{e.message}" if $VERBOSE
        []
      rescue ArgumentError => e
        return [] if e.message.include?('invalid byte sequence')

        raise
      end

      def deduplicate_discovered_entries(entries)
        entries.each_with_object({}) do |entry, deduplicated_entries|
          identity = [entry.resource_type, entry.key]
          existing_entry = deduplicated_entries[identity]
          if existing_entry.nil?
            deduplicated_entries[identity] = entry
            next
          end

          preferred_entry = if existing_entry.comment.to_s.empty? && !entry.comment.to_s.empty?
                              entry
                            else
                              existing_entry
                            end
          deduplicated_entries[identity] = DiscoveredLocalization.new(
            key: preferred_entry.key,
            file: preferred_entry.file,
            line: preferred_entry.line,
            text: preferred_entry.text,
            comment: preferred_entry.comment,
            resource_type: preferred_entry.resource_type,
            locations: (existing_entry.locations + entry.locations).uniq,
            location_groups: (existing_entry.location_groups + entry.location_groups).uniq
          )
        end.values
      end

      def platform_for_file(file)
        FileClassifier.searchable_platform(file, platform_hint: @platform)
      end

      def discover_ios_entries(file)
        lines = searchable_file_lines(file)
        entries = []
        index = 0

        while index < lines.length
          line = lines[index]
          next_index, discovered_entry = extract_ios_entry(lines, file, index, line)
          entries << discovered_entry if discovered_entry
          index = next_index || (index + 1)
        end

        entries
      end

      def extract_ios_entry(lines, file, index, line)
        if @localization_syntax.ios_call_start_patterns.any? { |pattern| pattern.match?(line) }
          next_index, discovered_entry = extract_ios_multiline_entry(lines, file, index)
          return [next_index, discovered_entry] if discovered_entry
        end

        if (entry = extract_ios_single_line_entry(file, index, line))
          return [index + 1, entry]
        end

        [index + 1, nil]
      end

      def extract_ios_single_line_entry(file, index, line)
        pattern = @localization_syntax.ios_single_line_discovery_patterns.find { |candidate| candidate.match?(line) }
        return unless pattern

        build_ios_discovered_entry(
          file,
          index,
          pattern.match(line),
          comment_match: IOS_COMMENT_ARGUMENT_PATTERN.match(line)
        )
      end

      def extract_ios_multiline_entry(lines, file, start_index, lookahead: 8)
        end_index = ios_call_end_index(lines, start_index, lookahead: lookahead)
        snippet = lines[start_index..end_index].join("\n")
        pattern = @localization_syntax.ios_multiline_discovery_patterns.find { |candidate| candidate.match?(snippet) }
        return [start_index + 1, nil] unless pattern

        match = pattern.match(snippet)
        key_line_index = locate_key_line(lines, start_index, end_index, match[:key])
        comment_match = IOS_COMMENT_ARGUMENT_PATTERN.match(snippet)
        locations = (start_index..end_index).map { |index| "#{file}:#{index + 1}" }

        [
          end_index + 1,
          build_ios_discovered_entry(
            file,
            key_line_index || start_index,
            match,
            comment_match: comment_match,
            locations: locations
          )
        ]
      end

      def build_ios_discovered_entry(file, index, match, comment_match: nil, locations: nil)
        key = match[:key]
        return if key.nil? || key.empty?

        text = match.names.include?('text') ? match[:text] : nil
        comment = if comment_match
                    unescape_source_string(comment_match[:comment])
                  elsif match.names.include?('comment')
                    unescape_source_string(match[:comment])
                  end
        text = unescape_source_string(text) if text

        DiscoveredLocalization.new(
          key: key,
          file: file,
          line: index + 1,
          text: text,
          comment: comment,
          locations: locations
        )
      end

      def ios_call_end_index(lines, start_index, lookahead:)
        maximum_index = [lines.length - 1, start_index + lookahead].min
        depth = 0
        found_opening = false

        (start_index..maximum_index).each do |index|
          parenthesis_delta(lines[index]).each do |delta|
            found_opening = true if delta.positive?
            depth += delta
          end
          return index if found_opening && depth <= 0
        end

        maximum_index
      end

      def parenthesis_delta(line)
        deltas = []
        quote = nil
        escaped = false

        line.each_char do |character|
          if quote
            if escaped
              escaped = false
            elsif character == '\\'
              escaped = true
            elsif character == quote
              quote = nil
            end
          elsif ["'", '"'].include?(character)
            quote = character
          elsif character == '('
            deltas << 1
          elsif character == ')'
            deltas << -1
          end
        end
        deltas
      end

      def locate_key_line(lines, start_index, end_index, key)
        (start_index..end_index).find do |index|
          lines[index].include?("\"#{key}\"") || lines[index].include?("@\"#{key}\"")
        end
      end

      def discover_android_entries(file)
        lines = searchable_file_lines(file)
        entries = []

        lines.each_with_index do |line, index|
          entries.concat(extract_android_entries_from_line(file, index, line))
        end

        entries
      end

      def extract_android_entries_from_line(file, index, line)
        @localization_syntax.android_discovery_patterns.flat_map do |resource_type, pattern|
          line.scan(pattern).filter_map do |captures|
            key = captures.compact.first
            next if key.nil? || key.empty?

            DiscoveredLocalization.new(
              key: key,
              file: file,
              line: index + 1,
              resource_type: resource_type
            )
          end
        end
      end

      def unescape_source_string(text)
        return if text.nil?

        text
          .gsub('\\"', '"')
          .gsub("\\'", "'")
          .gsub('\\\\', '\\')
          .gsub('\\n', "\n")
          .gsub('\\t', "\t")
      end
    end
  end
end
