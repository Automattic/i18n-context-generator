# frozen_string_literal: true

module I18nContextGenerator
  class Searcher
    # Source-discovery helpers used for source-first extraction runs.
    module SourceDiscovery
      IOS_SINGLE_LINE_DISCOVERY_PATTERNS = [
        /NSLocalizedString\s*\(\s*@?["'](?<key>[^"']+)["'](?:.*?comment:\s*["'](?<comment>(?:\\.|[^"'\\])*)["'])?/,
        /String\s*\(\s*localized:\s*["'](?<key>[^"']+)["'](?:.*?comment:\s*["'](?<comment>(?:\\.|[^"'\\])*)["'])?/,
        /LocalizedStringKey\s*\(\s*["'](?<key>[^"']+)["']\s*\)/,
        /:\s*LocalizedStringKey\s*=\s*["'](?<key>[^"']+)["']/,
        /Text\s*\(\s*["'](?<key>[^"']+)["']/,
        /["'](?<key>[^"']+)["']\.localized\b/
      ].freeze

      IOS_MULTILINE_DISCOVERY_PATTERNS = [
        /NSLocalizedString\s*\(\s*@?["'](?<key>[^"']+)["'](?:(?:(?!\)\s*[),]?)[\s\S])*?comment:\s*["'](?<comment>(?:\\.|[^"'\\])*)["'])?/,
        /String\s*\(\s*localized:\s*["'](?<key>[^"']+)["'](?:(?:(?!\)\s*[),]?)[\s\S])*?comment:\s*["'](?<comment>(?:\\.|[^"'\\])*)["'])?/,
        /Text\s*\(\s*LocalizedStringKey\s*\(\s*["'](?<key>[^"']+)["']\s*\)\s*\)/
      ].freeze

      ANDROID_DISCOVERY_PATTERNS = {
        string: %r{
          R\.string\.(\w+)\b|
          @string/([\w.]+)\b|
          [(\s,=]string\.(\w+)\b
        }x,
        plural: %r{
          R\.plurals\.(\w+)\b|
          @plurals/([\w.]+)\b|
          [(\s,=]plurals\.(\w+)\b
        }x,
        array: %r{
          R\.array\.(\w+)\b|
          @array/([\w.]+)\b|
          [(\s,=]array\.(\w+)\b
        }x
      }.freeze

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
            locations: (existing_entry.locations + entry.locations).uniq
          )
        end.values
      end

      def platform_for_file(file)
        case File.extname(file).downcase
        when '.swift', '.m', '.mm', '.h'
          :ios
        when '.kt', '.java'
          :android
        when '.xml'
          file.include?('/res/') ? :android : nil
        end
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
        if (entry = extract_ios_single_line_entry(file, index, line))
          return [index + 1, entry]
        end

        return extract_ios_multiline_entry(lines, file, index) if IOS_FUNCTION_OPENERS.any? { |opener| opener.match?(line) }

        [index + 1, nil]
      end

      def extract_ios_single_line_entry(file, index, line)
        pattern = IOS_SINGLE_LINE_DISCOVERY_PATTERNS.find { |candidate| candidate.match?(line) }
        return unless pattern

        build_ios_discovered_entry(file, index, pattern.match(line))
      end

      def extract_ios_multiline_entry(lines, file, start_index, lookahead: 8)
        end_index = [lines.length - 1, start_index + lookahead].min
        snippet = lines[start_index..end_index].join("\n")
        pattern = IOS_MULTILINE_DISCOVERY_PATTERNS.find { |candidate| candidate.match?(snippet) }
        return [start_index + 1, nil] unless pattern

        match = pattern.match(snippet)
        key_line_index = locate_key_line(lines, start_index, end_index, match[:key])

        [
          (key_line_index || start_index) + 1,
          build_ios_discovered_entry(file, key_line_index || start_index, match)
        ]
      end

      def build_ios_discovered_entry(file, index, match)
        key = match[:key]
        return if key.nil? || key.empty?

        text = match.names.include?('text') ? match[:text] : nil
        comment = match.names.include?('comment') ? unescape_source_string(match[:comment]) : nil
        text = unescape_source_string(text) if text

        DiscoveredLocalization.new(
          key: key,
          file: file,
          line: index + 1,
          text: text,
          comment: comment
        )
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
        ANDROID_DISCOVERY_PATTERNS.flat_map do |resource_type, pattern|
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
