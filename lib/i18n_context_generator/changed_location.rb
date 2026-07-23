# frozen_string_literal: true

module I18nContextGenerator
  # A line in a Git diff, including the revision side needed by review clients.
  #
  # `fallback_line` identifies a corresponding line in the head revision. It is
  # useful when a removed translator comment needs a right-side suggestion anchor.
  ChangedLocation = Data.define(:file, :line, :side, :fallback_line) do
    def initialize(file:, line:, side: :right, fallback_line: nil)
      normalized_side = side.to_s.downcase.to_sym
      raise ArgumentError, "Unsupported diff side: #{side}" unless %i[left right].include?(normalized_side)

      super(
        file: file.to_s,
        line: Integer(line),
        side: normalized_side,
        fallback_line: fallback_line && Integer(fallback_line)
      )
    end

    def self.parse(value)
      return value if value.is_a?(self)

      match = /\A(.+):(\d+)\z/.match(value.to_s)
      raise ArgumentError, "Invalid changed location: #{value.inspect}" unless match

      new(file: match[1], line: match[2], side: :right)
    end

    def left?
      side == :left
    end

    def right?
      side == :right
    end

    def review_side
      side.to_s.upcase
    end

    def to_s
      "#{file}:#{line}"
    end

    def to_h
      {
        file: file,
        line: line,
        side: side,
        fallback_line: fallback_line
      }
    end
  end
end
