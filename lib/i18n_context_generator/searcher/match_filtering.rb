# frozen_string_literal: true

module I18nContextGenerator
  class Searcher
    # Removes duplicate, translation-definition, and non-localization matches.
    module MatchFiltering
      private

      def filter_matches(matches, key)
        seen = Set.new
        matches.select do |match|
          location = "#{match.file}:#{match.line}"
          next false if seen.include?(location)
          next false if false_positive?(match.match_line, key)
          next false if translation_file?(match.file)

          seen.add(location)
        end
      end

      def false_positive?(line, key)
        return false if line.nil? || line.empty?
        return false if explicit_localization_usage?(line, key)

        quoted_key = "[\"']#{Regexp.escape(key)}[\"']"
        comparison_patterns = [
          /==\s*#{quoted_key}/,
          /#{quoted_key}\s*==/,
          /!=\s*#{quoted_key}/,
          /#{quoted_key}\s*!=/,
          /\.equals\(\s*#{quoted_key}/,
          /contentEquals\(\s*#{quoted_key}/
        ]

        comparison_patterns.any? { |pattern| pattern.match?(line) }
      end

      def explicit_localization_usage?(line, key)
        patterns = build_ios_patterns(key) + build_android_patterns(key)
        patterns.any? { |pattern| Regexp.new(pattern).match?(line) }
      end

      def translation_file?(file)
        basename = File.basename(file).downcase
        ext = File.extname(file).downcase

        return true if ext == '.strings'
        return true if basename == 'strings.xml'
        return true if file.include?('/res/values') && ext == '.xml'

        false
      end
    end
  end
end
