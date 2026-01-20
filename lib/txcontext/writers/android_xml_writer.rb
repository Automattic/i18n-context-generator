# frozen_string_literal: true

require "rexml/document"

module Txcontext
  module Writers
    # Writer that updates Android strings.xml files with context comments
    # Uses REXML for proper XML manipulation
    class AndroidXmlWriter
      def initialize(context_prefix: "Context: ", context_mode: "replace")
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      def write(results, source_path)
        return unless File.exist?(source_path)

        content = File.read(source_path, encoding: "UTF-8")
        doc = REXML::Document.new(content)
        results_by_key = results.to_h { |r| [r.key, r] }

        # Process each string element
        doc.elements.each("resources/string") do |element|
          key = element.attributes["name"]
          result = results_by_key[key]

          next unless result&.description
          next if skip_description?(result.description)

          update_element_comment(element, result.description)
        end

        # Write back with preserved formatting
        output = String.new
        formatter = REXML::Formatters::Pretty.new(4)
        formatter.compact = true
        formatter.write(doc, output)

        # Fix common formatting issues
        output = fix_formatting(output, content)

        File.write(source_path, output)
      end

      private

      def skip_description?(description)
        description.include?("No usage found") || description.include?("Processing failed")
      end

      def update_element_comment(element, description)
        context_text = "#{@context_prefix}#{escape_comment(description)}"

        # Find existing comment before this element
        prev_sibling = element.previous_sibling

        # Skip whitespace text nodes
        while prev_sibling.is_a?(REXML::Text) && prev_sibling.to_s.strip.empty?
          prev_sibling = prev_sibling.previous_sibling
        end

        if prev_sibling.is_a?(REXML::Comment)
          existing_text = prev_sibling.to_s.strip

          if @context_mode == "replace"
            # Replace entire comment
            prev_sibling.string = " #{context_text} "
          elsif !@context_prefix.empty? && existing_text.start_with?(@context_prefix)
            # Update existing context line (idempotent)
            prev_sibling.string = " #{context_text} "
          else
            # Append to existing comment
            prev_sibling.string = " #{existing_text} #{context_text} "
          end
        else
          # Insert new context comment before the element
          insert_comment_before(element, context_text)
        end
      end

      def insert_comment_before(element, text)
        parent = element.parent
        index = parent.index(element)

        # Create comment node
        comment = REXML::Comment.new(" #{text} ")

        # Insert comment and a newline before the element
        parent.insert_before(element, comment)
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text
          .gsub("--", "- -") # Double dash not allowed in XML comments
          .gsub("\n", " ")
          .strip
      end

      def fix_formatting(output, original_content)
        # Preserve original XML declaration style if present
        if original_content.start_with?("<?xml")
          original_decl = original_content.match(/^<\?xml[^?]*\?>/)[0]
          output = output.sub(/^<\?xml[^?]*\?>/, original_decl)
        end

        # Ensure file ends with newline
        output = "#{output.rstrip}\n"

        output
      end
    end
  end
end
