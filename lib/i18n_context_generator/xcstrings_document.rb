# frozen_string_literal: true

require 'json'
require 'oj'

module I18nContextGenerator
  # Structural index for an Apple string catalog that retains byte offsets in
  # the original JSON. It lets write-back edit only owned comment values and
  # lets diff handling map revision-specific line numbers without reformatting.
  class XcstringsDocument
    Member = Data.define(:key, :key_start, :key_end, :value_start, :value_end, :separator)

    attr_reader :catalog

    def initialize(content, path:)
      @content = content
      @path = path
      @catalog = Oj.load(content, mode: :strict)
      @line_starts = [0]
      content.each_char.with_index { |character, index| @line_starts << (index + 1) if character == "\n" }
      @root_members = object_members(skip_whitespace(0))
      strings_member = @root_members.find { |member| member.key == 'strings' }
      raise TypeError, 'strings must be a mapping' unless strings_member && @content[strings_member.value_start] == '{'

      @strings_member = strings_member
      @entry_members = object_members(strings_member.value_start)
      @entries_by_key = @entry_members.to_h { |member| [member.key, member] }
    rescue Oj::ParseError, TypeError => e
      raise Error, "Failed to parse Apple string catalog #{path}: #{e.message}"
    end

    def line_index
      @entry_members.each_with_object({}) do |member, index|
        start_line = line_number(member.key_start)
        end_line = line_number(member.value_end - 1)
        (start_line..end_line).each { |line| index[line] = member.key }
      end
    end

    def with_comments(comments_by_key)
      edits = comments_by_key.filter_map do |key, comment|
        entry_member = @entries_by_key[key]
        next unless entry_member && @content[entry_member.value_start] == '{'
        next if @catalog.dig('strings', key, 'comment') == comment

        comment_edit(entry_member, comment)
      end
      return @content if edits.empty?

      rendered = @content.dup
      edits.sort_by(&:first).reverse_each do |start_offset, end_offset, replacement|
        rendered[start_offset...end_offset] = replacement
      end
      rendered
    end

    private

    def comment_edit(entry_member, comment)
      children = object_members(entry_member.value_start)
      existing = children.find { |member| member.key == 'comment' }
      encoded_comment = JSON.generate(comment)
      return [existing.value_start, existing.value_end, encoded_comment] if existing

      insert_comment_edit(entry_member, children, encoded_comment)
    end

    def insert_comment_edit(entry_member, children, encoded_comment)
      entry_indent = line_indent(entry_member.key_start)
      child_indent = children.empty? ? "#{entry_indent}#{indent_unit}" : line_indent(children.first.key_start)
      child_indent = "#{entry_indent}#{indent_unit}" unless child_indent.match?(/\A\s*\z/)
      separator = children.first&.separator || entry_member.separator
      rendered_comment = "#{child_indent}\"comment\"#{separator}#{encoded_comment}"

      if children.empty?
        interior_start = entry_member.value_start + 1
        interior_end = entry_member.value_end - 1
        replacement = "#{newline}#{rendered_comment}#{newline}#{entry_indent}"
        [interior_start, interior_end, replacement]
      else
        insertion_point = entry_member.value_start + 1
        [insertion_point, insertion_point, "#{newline}#{rendered_comment},"]
      end
    end

    def indent_unit
      @indent_unit ||= begin
        strings_indent = line_indent(@strings_member.key_start)
        entry_indent = line_indent(@entry_members.first&.key_start || @strings_member.key_start)
        difference = entry_indent.delete_prefix(strings_indent)
        difference.empty? ? '  ' : difference
      end
    end

    def newline
      @newline ||= @content.include?("\r\n") ? "\r\n" : "\n"
    end

    def line_indent(offset)
      line_start = @content.rindex("\n", offset - 1)
      @content[(line_start ? line_start + 1 : 0)...offset]
    end

    def line_number(offset)
      @line_starts.bsearch_index { |line_start| line_start > offset } || @line_starts.length
    end

    def object_members(object_start)
      raise TypeError, "expected object at byte #{object_start}" unless @content[object_start] == '{'

      members = []
      cursor = skip_whitespace(object_start + 1)
      return members if @content[cursor] == '}'

      loop do
        key_start = cursor
        key_end = string_end(key_start)
        key = JSON.parse(@content[key_start...key_end])
        cursor = skip_whitespace(key_end)
        raise TypeError, "expected ':' at byte #{cursor}" unless @content[cursor] == ':'

        cursor = skip_whitespace(cursor + 1)
        value_start = cursor
        value_end = value_end(value_start)
        members << Member.new(
          key: key,
          key_start: key_start,
          key_end: key_end,
          value_start: value_start,
          value_end: value_end,
          separator: @content[key_end...value_start]
        )
        cursor = skip_whitespace(value_end)
        break if @content[cursor] == '}'

        raise TypeError, "expected ',' at byte #{cursor}" unless @content[cursor] == ','

        cursor = skip_whitespace(cursor + 1)
      end

      members
    end

    def value_end(start_offset)
      case @content[start_offset]
      when '"'
        string_end(start_offset)
      when '{'
        collection_end(start_offset, '{', '}')
      when '['
        collection_end(start_offset, '[', ']')
      else
        primitive_end(start_offset)
      end
    end

    def string_end(start_offset)
      cursor = start_offset + 1
      escaped = false
      while cursor < @content.length
        character = @content[cursor]
        if escaped
          escaped = false
        elsif character == '\\'
          escaped = true
        elsif character == '"'
          return cursor + 1
        end
        cursor += 1
      end
      raise TypeError, "unterminated string at byte #{start_offset}"
    end

    def collection_end(start_offset, opening, closing)
      depth = 0
      cursor = start_offset
      while cursor < @content.length
        character = @content[cursor]
        case character
        when '"'
          cursor = string_end(cursor)
          next
        when opening
          depth += 1
        when closing
          depth -= 1
          return cursor + 1 if depth.zero?
        end
        cursor += 1
      end
      raise TypeError, "unterminated collection at byte #{start_offset}"
    end

    def primitive_end(start_offset)
      cursor = start_offset
      cursor += 1 while cursor < @content.length && !",}] \t\r\n".include?(@content[cursor])
      cursor
    end

    def skip_whitespace(offset)
      cursor = offset
      cursor += 1 while cursor < @content.length && @content[cursor].match?(/\s/)
      cursor
    end
  end
end
