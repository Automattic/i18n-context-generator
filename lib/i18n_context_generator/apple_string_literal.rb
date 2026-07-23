# frozen_string_literal: true

module I18nContextGenerator
  # Shared parsing and decoding for Apple/Swift quoted string literals.
  module AppleStringLiteral
    BODY_PATTERN = '(?:\\\\.|[^"\\\\])*'
    ASSIGNMENT_PATTERN = /\A\s*"(?<key>#{BODY_PATTERN})"\s*=/

    module_function

    def assignment_key(content)
      match = ASSIGNMENT_PATTERN.match(content)
      decode(match[:key]) if match
    end

    def decode(content)
      return if content.nil?

      content
        .gsub('\\"', '"')
        .gsub("\\'", "'")
        .gsub('\\\\', '\\')
        .gsub('\\n', "\n")
        .gsub('\\r', "\r")
        .gsub('\\t', "\t")
    end
  end
end
