# frozen_string_literal: true

module I18nContextGenerator
  class Searcher
    # Removes duplicate, translation-definition, and non-localization matches.
    module MatchFiltering
      private

      def filter_matches(matches, key)
        seen = Set.new
        explicit_patterns = explicit_localization_patterns(key)
        matches.select do |match|
          location = "#{match.file}:#{match.line}"
          next false if seen.include?(location)
          next false if false_positive?(match.match_line, key, explicit_patterns)
          next false if translation_file?(match.file)

          seen.add(location)
        end
      end

      def false_positive?(line, key, explicit_patterns)
        return false if line.nil? || line.empty?
        return false if explicit_localization_usage?(line, explicit_patterns)

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

      def explicit_localization_patterns(key)
        (build_ios_patterns(key) + build_android_patterns(key)).map { |pattern| Regexp.new(pattern) }
      end

      def explicit_localization_usage?(line, patterns)
        patterns.any? { |pattern| pattern.match?(line) }
      end

      def translation_file?(file)
        !FileClassifier.translation_platform(file).nil?
      end
    end
  end
end
