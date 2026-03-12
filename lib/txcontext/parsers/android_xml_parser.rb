# frozen_string_literal: true

require 'rexml/document'

module Txcontext
  module Parsers
    # Parser for Android strings.xml files
    # Format: <string name="key">value</string>
    # With optional comment: <!-- comment --> <string name="key">value</string>
    class AndroidXmlParser < Base
      def parse(path)
        content = File.read(path, encoding: 'UTF-8')
        doc = REXML::Document.new(content)
        entries = []

        doc.elements.each('resources/string') do |element|
          key = element.attributes['name']
          text = inner_text(element)

          # Look for preceding comment
          comment = find_preceding_comment(element)

          entries << TranslationEntry.new(
            key: key,
            text: unescape_android_string(text),
            source_file: path,
            metadata: { comment: comment }
          )
        end

        # Also parse string arrays
        doc.elements.each('resources/string-array') do |array_element|
          array_name = array_element.attributes['name']
          array_element.elements.to_a('item').each_with_index do |item, index|
            entries << TranslationEntry.new(
              key: "#{array_name}[#{index}]",
              text: unescape_android_string(inner_text(item)),
              source_file: path,
              metadata: { array: array_name, index: index }
            )
          end
        end

        # Also parse plurals
        doc.elements.each('resources/plurals') do |plural_element|
          plural_name = plural_element.attributes['name']
          plural_element.elements.each('item') do |item|
            quantity = item.attributes['quantity']
            entries << TranslationEntry.new(
              key: "#{plural_name}:#{quantity}",
              text: unescape_android_string(inner_text(item)),
              source_file: path,
              metadata: { plural: plural_name, quantity: quantity }
            )
          end
        end

        entries
      end

      private

      # Get the full inner content of an element, including inline markup like
      # <b>, <i>, <u>, <xliff:g>. REXML::Element#text only returns the first
      # text node, losing everything after a nested element.
      def inner_text(element)
        element.children.map { |child|
          child.is_a?(REXML::Text) ? child.value : child.to_s
        }.join
      end

      def find_preceding_comment(element)
        # Look at the previous sibling
        prev = element.previous_sibling
        while prev
          if prev.is_a?(REXML::Comment)
            return prev.to_s.strip
          elsif prev.is_a?(REXML::Element)
            # Hit another element, stop looking
            return nil
          end

          prev = prev.previous_sibling
        end
        nil
      end

      # Unescape Android string escapes
      def unescape_android_string(str)
        str
          .gsub("\\'", "'")
          .gsub('\\"', '"')
          .gsub('\\n', "\n")
          .gsub('\\t', "\t")
          .gsub('\\@', '@')
          .gsub('\\?', '?')
      end
    end
  end
end
