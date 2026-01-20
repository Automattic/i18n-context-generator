# frozen_string_literal: true

module Txcontext
  module Parsers
    # Parser for Apple .strings files (iOS/macOS)
    # Uses the dotstrings gem for proper parsing with support for:
    # - Multi-line comments
    # - Unicode and escaped characters
    # - Proper error handling
    class StringsParser < Base
      def parse(path)
        # Use non-strict mode to be lenient with edge cases
        strings_file = DotStrings.parse_file(path, strict: false)

        strings_file.items.map do |item|
          TranslationEntry.new(
            key: item.key,
            text: item.value,
            source_file: path,
            metadata: { comment: item.comment }
          )
        end
      rescue DotStrings::ParsingError => e
        raise Error, "Failed to parse .strings file #{path}: #{e.message}"
      end
    end
  end
end
