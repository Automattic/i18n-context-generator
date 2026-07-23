# frozen_string_literal: true

module I18nContextGenerator
  # Small stateful XML scanning helpers for line-oriented diff and location code.
  # This is intentionally not an XML parser; it only removes comments while
  # preserving the remaining text and line boundaries.
  module XmlScanner
    module_function

    def without_comments(line, state)
      remaining = line.to_s
      visible = +''
      contained_comment = false

      loop do
        if state[:inside_comment]
          contained_comment = true
          comment_end = remaining.index('-->')
          return [visible, contained_comment] unless comment_end

          state[:inside_comment] = false
          remaining = remaining[(comment_end + 3)..].to_s
        else
          comment_start = remaining.index('<!--')
          unless comment_start
            visible << remaining
            return [visible, contained_comment]
          end

          visible << remaining[0...comment_start]
          contained_comment = true
          state[:inside_comment] = true
          remaining = remaining[(comment_start + 4)..].to_s
        end
      end
    end
  end
end
