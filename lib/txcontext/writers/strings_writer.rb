# frozen_string_literal: true

module Txcontext
  module Writers
    # Writer that updates iOS .strings files with context comments
    # Uses the dotstrings gem for proper parsing and generation
    class StringsWriter
      CONTEXT_PREFIX = "Context: "

      def write(results, source_path)
        return unless File.exist?(source_path)

        # Parse the existing file
        original_file = DotStrings.parse_file(source_path, strict: false)
        results_by_key = results.to_h { |r| [r.key, r] }

        # Build new file with updated comments (DotStrings::Item is immutable)
        new_file = DotStrings::File.new

        original_file.items.each do |item|
          result = results_by_key[item.key]

          new_comment = if result&.description && !skip_description?(result.description)
                          build_comment(item.comment, result.description)
                        else
                          item.comment
                        end

          new_item = DotStrings::Item.new(
            key: item.key,
            value: item.value,
            comment: new_comment
          )
          new_file << new_item
        end

        # Write back to file
        File.write(source_path, new_file.to_s)
      end

      private

      def skip_description?(description)
        description.include?("No usage found") || description.include?("Processing failed")
      end

      def build_comment(existing_comment, context_description)
        context_line = "#{CONTEXT_PREFIX}#{context_description}"

        if existing_comment.nil? || existing_comment.empty?
          context_line
        elsif existing_comment.include?(CONTEXT_PREFIX)
          # Replace existing context line
          existing_comment.gsub(/#{Regexp.escape(CONTEXT_PREFIX)}[^\n]*/, context_line)
        else
          # Append context to existing comment
          "#{existing_comment}\n#{context_line}"
        end
      end
    end
  end
end
