# frozen_string_literal: true

require_relative 'xml_scanner'
require_relative 'apple_string_literal'

module I18nContextGenerator
  # Associates translator-comment lines with the translation entry that follows.
  # Diff consumers use this to treat comment-only edits as entry changes while
  # retaining the exact changed comment line for review placement.
  class TranslationCommentIndex
    def initialize(file_path = nil, format:, content: nil)
      @file_path = file_path
      @format = format
      @content = content || File.binread(file_path)
      @key_lines = {}
    end

    def key_at(line_number)
      entries[line_number]
    end

    def line_for_key(key)
      entries
      @key_lines[key]
    end

    private

    def entries
      @entries ||= case @format
                   when :strings then strings_entries
                   when :xml then xml_entries
                   else {}
                   end
    end

    def strings_entries
      entries = {}
      pending_lines = []
      inside_comment = false

      @content.each_line.with_index(1) do |line, line_number|
        content = line

        if inside_comment
          pending_lines << line_number
          comment_end = content.index('*/')
          next unless comment_end

          inside_comment = false
          content = content[(comment_end + 2)..].to_s
        elsif (comment_start = content.index(%r{\A\s*/\*}))
          pending_lines << line_number
          comment_end = content.index('*/', comment_start + 2)
          unless comment_end
            inside_comment = true
            next
          end
          content = content[(comment_end + 2)..].to_s
        elsif content.lstrip.start_with?('//')
          pending_lines << line_number
          next
        end

        if (key = strings_key_from(content))
          @key_lines[key] ||= line_number
          pending_lines.each { |comment_line| entries[comment_line] = key }
          pending_lines.clear
        elsif !content.strip.empty?
          pending_lines.clear
        end
      end

      entries
    end

    def strings_key_from(content)
      AppleStringLiteral.assignment_key(content)
    end

    def xml_entries
      entries = {}
      pending_lines = []
      pending_tag = nil
      pending_tag_line = nil
      comment_state = {}

      @content.each_line.with_index(1) do |line, line_number|
        visible, contained_comment = XmlScanner.without_comments(line, comment_state)
        pending_lines << line_number if contained_comment

        if pending_tag
          pending_tag << visible
        elsif (tag_start = visible.index(/<(?:string-array|plurals|string)\b/))
          pending_tag = visible[tag_start..]
          pending_tag_line = line_number
        elsif !visible.strip.empty?
          pending_lines.clear
        end

        next unless pending_tag&.include?('>')

        if (key = resource_name_from(pending_tag))
          @key_lines[key] ||= pending_tag_line
          pending_lines.each { |comment_line| entries[comment_line] = key }
        end
        pending_lines.clear
        pending_tag = nil
        pending_tag_line = nil
      end

      entries
    end

    def resource_name_from(tag)
      return unless tag.match?(/<(?:string-array|plurals|string)\b/)

      tag[/\bname\s*=\s*(["'])(.*?)\1/m, 2]
    end
  end
end
