# frozen_string_literal: true

module Txcontext
  module Writers
    # Writer that updates iOS .strings files with context comments
    # Adds or updates comments before each string entry
    class StringsWriter
      def write(results, source_path)
        return unless File.exist?(source_path)

        content = File.read(source_path, encoding: "UTF-8")
        results_by_key = results.to_h { |r| [r.key, r] }

        updated_content = update_content(content, results_by_key)

        File.write(source_path, updated_content)
      end

      private

      def update_content(content, results_by_key)
        lines = content.lines
        output_lines = []
        i = 0

        while i < lines.length
          line = lines[i]

          # Check if this is a string entry
          if (match = line.match(/^\s*"([^"]+)"\s*=\s*"(.*)"\s*;\s*$/))
            key = match[1]

            if results_by_key[key] && results_by_key[key].description
              description = results_by_key[key].description

              # Skip "No usage found" or error descriptions
              unless description.include?("No usage found") || description.include?("Processing failed")
                # Check if previous line is already a context comment (to replace it)
                if output_lines.any? && output_lines.last.match?(%r{^\s*/\*.*\*/\s*$})
                  # Check if it's a context comment (not a section header or other comment)
                  prev_comment = output_lines.last
                  if prev_comment.include?("Context:") || !prev_comment.match?(/^\/\*\s*(MARK|TODO|FIXME|#pragma)/)
                    output_lines.pop # Remove old context comment
                  end
                end

                # Add new context comment
                output_lines << "/* Context: #{escape_comment(description)} */\n"
              end
            end
          end

          output_lines << line
          i += 1
        end

        output_lines.join
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text.gsub("*/", "* /").gsub("/*", "/ *").gsub("\n", " ").strip
      end
    end
  end
end
