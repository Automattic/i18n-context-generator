# frozen_string_literal: true

module I18nContextGenerator
  class Searcher
    # Masks comments while preserving line numbers and character positions.
    module CommentMasking
      private

      def mask_comments(lines, file)
        File.extname(file).downcase == '.xml' ? mask_xml_comments(lines) : mask_c_style_comments(lines)
      end

      def mask_c_style_comments(lines)
        block_depth = 0

        lines.map do |line|
          masked = line.dup
          quote = nil
          escaped = false
          index = 0

          while index < line.length
            pair = line[index, 2]

            if block_depth.positive?
              if pair == '/*'
                mask_characters!(masked, index, 2)
                block_depth += 1
                index += 2
              elsif pair == '*/'
                mask_characters!(masked, index, 2)
                block_depth -= 1
                index += 2
              else
                mask_characters!(masked, index, 1)
                index += 1
              end
              next
            end

            if quote
              if escaped
                escaped = false
              elsif line[index] == '\\'
                escaped = true
              elsif line[index] == quote
                quote = nil
              end
              index += 1
              next
            end

            if pair == '//'
              mask_characters!(masked, index, line.length - index)
              break
            elsif pair == '/*'
              mask_characters!(masked, index, 2)
              block_depth = 1
              index += 2
            elsif ['"', "'"].include?(line[index])
              quote = line[index]
              index += 1
            else
              index += 1
            end
          end

          masked
        end
      end

      def mask_xml_comments(lines)
        in_comment = false

        lines.map do |line|
          masked = line.dup
          index = 0

          while index < line.length
            if in_comment
              closing_index = line.index('-->', index)
              if closing_index
                mask_characters!(masked, index, closing_index + 3 - index)
                index = closing_index + 3
                in_comment = false
              else
                mask_characters!(masked, index, line.length - index)
                break
              end
            else
              opening_index = line.index('<!--', index)
              break unless opening_index

              closing_index = line.index('-->', opening_index + 4)
              if closing_index
                mask_characters!(masked, opening_index, closing_index + 3 - opening_index)
                index = closing_index + 3
              else
                mask_characters!(masked, opening_index, line.length - opening_index)
                in_comment = true
                break
              end
            end
          end

          masked
        end
      end

      def mask_characters!(text, start, length)
        text[start, length] = ' ' * length
      end
    end
  end
end
