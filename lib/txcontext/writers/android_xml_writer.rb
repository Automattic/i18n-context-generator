# frozen_string_literal: true

require "rexml/document"
require "rexml/formatters/pretty"

module Txcontext
  module Writers
    # Writer that updates Android strings.xml files with context comments
    # Adds or updates comments before each string entry
    class AndroidXmlWriter
      def write(results, source_path)
        return unless File.exist?(source_path)

        content = File.read(source_path, encoding: "UTF-8")
        results_by_key = results.to_h { |r| [r.key, r] }

        updated_content = update_content(content, results_by_key)

        File.write(source_path, updated_content)
      end

      private

      def update_content(content, results_by_key)
        # Use line-based processing to preserve formatting
        lines = content.lines
        output_lines = []
        i = 0

        while i < lines.length
          line = lines[i]

          # Check if this is a string element
          if (match = line.match(/<string\s+name="([^"]+)"[^>]*>/))
            key = match[1]

            if results_by_key[key] && results_by_key[key].description
              description = results_by_key[key].description

              # Skip "No usage found" or error descriptions
              unless description.include?("No usage found") || description.include?("Processing failed")
                # Check if previous non-empty line is already a context comment
                prev_index = output_lines.length - 1
                while prev_index >= 0 && output_lines[prev_index].strip.empty?
                  prev_index -= 1
                end

                if prev_index >= 0 && output_lines[prev_index].match?(/^\s*<!--.*-->\s*$/)
                  prev_comment = output_lines[prev_index]
                  # Replace if it's a context comment
                  if prev_comment.include?("Context:")
                    output_lines[prev_index] = "#{indent(line)}<!-- Context: #{escape_comment(description)} -->\n"
                  else
                    # Add new context comment before the string
                    output_lines << "#{indent(line)}<!-- Context: #{escape_comment(description)} -->\n"
                  end
                else
                  # Add new context comment
                  output_lines << "#{indent(line)}<!-- Context: #{escape_comment(description)} -->\n"
                end
              end
            end
          end

          output_lines << line
          i += 1
        end

        output_lines.join
      end

      def indent(line)
        line.match(/^(\s*)/)[1] || ""
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text.gsub("-->", "- ->").gsub("<!--", "<!- -").gsub("\n", " ").strip
      end
    end
  end
end
