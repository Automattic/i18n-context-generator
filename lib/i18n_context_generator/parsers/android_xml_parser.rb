# frozen_string_literal: true

require 'rexml/document'
require_relative '../android_resource'

module I18nContextGenerator
  module Parsers
    # Parser for Android strings.xml files
    # Format: <string name="key">value</string>
    # With optional comment: <!-- comment --> <string name="key">value</string>
    class AndroidXmlParser < Base
      def parse(path)
        content = File.read(path, encoding: 'UTF-8')
        doc = REXML::Document.new(content)
        resource_index = AndroidResource.index(content)
        entries = []

        doc.elements.each('resources/string') do |element|
          next unless translatable?(element)

          key = element.attributes['name']
          text = inner_text(element)

          # Look for preceding comment
          comment = find_preceding_comment(element)

          entries << build_entry(
            key: key,
            text: unescape_android_string(text),
            source_file: path,
            metadata: { comment: comment, resource_type: :string },
            resource_index: resource_index
          )
        end

        # Also parse string arrays
        doc.elements.each('resources/string-array') do |array_element|
          next unless translatable?(array_element)

          array_name = array_element.attributes['name']
          array_element.elements.to_a('item').each_with_index do |item, index|
            key = AndroidResource.composite_key(array_name, type: :array, index: index)
            entries << build_entry(
              key: key,
              text: unescape_android_string(inner_text(item)),
              source_file: path,
              metadata: { array: array_name, index: index, resource_type: :array },
              resource_index: resource_index
            )
          end
        end

        # Also parse plurals
        doc.elements.each('resources/plurals') do |plural_element|
          next unless translatable?(plural_element)

          plural_name = plural_element.attributes['name']
          plural_element.elements.each('item') do |item|
            quantity = item.attributes['quantity']
            key = AndroidResource.composite_key(plural_name, type: :plural, quantity: quantity)
            entries << build_entry(
              key: key,
              text: unescape_android_string(inner_text(item)),
              source_file: path,
              metadata: { plural: plural_name, quantity: quantity, resource_type: :plural },
              resource_index: resource_index
            )
          end
        end

        entries
      rescue REXML::ParseException => e
        raise Error, "Failed to parse Android XML translation file #{path}: #{e.message.lines.first&.strip}"
      end

      private

      def build_entry(key:, text:, source_file:, metadata:, resource_index:)
        span = resource_index.span_for(key)
        if span
          metadata = metadata.merge(
            line_span: span.line_span,
            resource_line_span: span.parent_line_span
          )
        end
        TranslationEntry.new(key: key, text: text, source_file: source_file, metadata: metadata)
      end

      # Get the full inner content of an element, including inline markup like
      # <b>, <i>, <u>, <xliff:g>. REXML::Element#text only returns the first
      # text node, losing everything after a nested element.
      def inner_text(element)
        element.children.map do |child|
          child.is_a?(REXML::Text) ? child.value : child.to_s
        end.join
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

      def translatable?(element)
        element.attributes['translatable']&.downcase != 'false'
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
