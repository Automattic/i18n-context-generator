# frozen_string_literal: true

module Txcontext
  module Parsers
    # Parser for Apple .strings files (iOS/macOS)
    # Format: "key" = "value";
    # With optional comment: /* comment */ "key" = "value";
    class StringsParser < Base
      # Match: "key" = "value";
      # Captures: key, value
      STRING_PATTERN = /^\s*"([^"]+)"\s*=\s*"(.*)"\s*;\s*$/

      # Match: /* comment */
      COMMENT_PATTERN = %r{/\*\s*(.*?)\s*\*/}m

      def parse(path)
        content = File.read(path, encoding: "UTF-8")
        entries = []
        current_comment = nil

        content.each_line do |line|
          # Check for comment
          if (comment_match = line.match(COMMENT_PATTERN))
            current_comment = comment_match[1].strip
          end

          # Check for string entry
          if (string_match = line.match(STRING_PATTERN))
            key = string_match[1]
            text = unescape_string(string_match[2])

            entries << TranslationEntry.new(
              key: key,
              text: text,
              source_file: path,
              metadata: { comment: current_comment }
            )

            # Reset comment after using it
            current_comment = nil
          end
        end

        entries
      end

      private

      # Unescape common escape sequences in .strings files
      def unescape_string(str)
        str
          .gsub('\\"', '"')
          .gsub("\\n", "\n")
          .gsub("\\t", "\t")
          .gsub("\\\\", "\\")
      end
    end
  end
end
