# frozen_string_literal: true

module Txcontext
  module Writers
    # Writer that updates Android strings.xml files with context comments
    # Uses line-by-line approach to preserve original formatting
    class AndroidXmlWriter
      def initialize(context_prefix: "Context: ", context_mode: "replace")
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      def write(results, source_path)
        return unless File.exist?(source_path)

        lines = File.readlines(source_path, encoding: "UTF-8")
        results_by_key = results.to_h { |r| [r.key, r] }

        output_lines = []
        i = 0

        while i < lines.length
          line = lines[i]

          # Check if this line is a string element
          if (match = line.match(/^(\s*)<string\s+name="([^"]+)"[^>]*>.*<\/string>\s*$/))
            indent = match[1]
            key = match[2]
            result = results_by_key[key]

            if result&.description && !skip_description?(result.description)
              context_text = "#{@context_prefix}#{escape_comment(result.description)}"

              # Check if previous line is a comment
              if output_lines.any? && output_lines.last.match?(/^\s*<!--.*-->\s*$/)
                # Update existing comment
                existing_comment_line = output_lines.pop
                existing_match = existing_comment_line.match(/^\s*<!--\s*(.*?)\s*-->\s*$/)
                existing_comment = existing_match ? existing_match[1] : ""
                new_comment = build_comment(existing_comment, context_text)
                output_lines << "#{indent}<!-- #{new_comment} -->\n"
              else
                # Insert new comment
                output_lines << "#{indent}<!-- #{context_text} -->\n"
              end
            end
          end

          output_lines << line
          i += 1
        end

        File.write(source_path, output_lines.join)
      end

      private

      def skip_description?(description)
        description.include?("No usage found") || description.include?("Processing failed")
      end

      def build_comment(existing_comment, context_text)
        if existing_comment.nil? || existing_comment.empty?
          context_text
        elsif @context_mode == "replace"
          # Replace entire comment with new context
          context_text
        elsif !@context_prefix.empty? && existing_comment.include?(@context_prefix)
          # Replace existing context line (idempotent update)
          existing_comment.gsub(/#{Regexp.escape(@context_prefix)}[^\n]*/, context_text)
        else
          # Append context to existing comment
          "#{existing_comment} #{context_text}"
        end
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text
          .gsub("--", "- -") # Double dash not allowed in XML comments
          .gsub("\n", " ")
          .strip
      end
    end
  end
end
