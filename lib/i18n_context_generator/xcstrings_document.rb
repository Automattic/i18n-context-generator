# frozen_string_literal: true

require 'json'
require 'oj'

module I18nContextGenerator
  # Structural index for an Apple string catalog that retains byte offsets in
  # the original JSON. It lets write-back edit only owned comment values and
  # lets diff handling map revision-specific line numbers without reformatting.
  class XcstringsDocument
    Member = Data.define(:key, :key_start, :key_end, :value_start, :value_end, :separator)
    BYTE = {
      backslash: '\\'.ord,
      close_array: ']'.ord,
      close_object: '}'.ord,
      colon: ':'.ord,
      comma: ','.ord,
      newline: "\n".ord,
      open_array: '['.ord,
      open_object: '{'.ord,
      quote: '"'.ord
    }.freeze
    JSON_WHITESPACE_BYTES = ["\t".ord, "\n".ord, "\r".ord, ' '.ord].freeze
    PRIMITIVE_TERMINATOR_BYTES = [
      BYTE[:comma],
      BYTE[:close_object],
      BYTE[:close_array],
      *JSON_WHITESPACE_BYTES
    ].freeze
    private_constant :BYTE, :JSON_WHITESPACE_BYTES, :PRIMITIVE_TERMINATOR_BYTES

    attr_reader :catalog

    def initialize(content, path:)
      @content = content
      @path = path
      @catalog = Oj.load(content, mode: :strict)
      @line_starts = [0]
      content.each_byte.with_index { |byte, index| @line_starts << (index + 1) if byte == BYTE[:newline] }
      @root_members = object_members(skip_whitespace(0))
      strings_member = @root_members.find { |member| member.key == 'strings' }
      strings_object = strings_member && byte_at(strings_member.value_start) == BYTE[:open_object]
      raise TypeError, 'strings must be a mapping' unless strings_object

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
        next unless entry_member && byte_at(entry_member.value_start) == BYTE[:open_object]
        next if @catalog.dig('strings', key, 'comment') == comment

        comment_edit(entry_member, comment)
      end
      return @content if edits.empty?

      original_encoding = @content.encoding
      rendered = @content.b
      edits.sort_by(&:first).reverse_each do |start_offset, end_offset, replacement|
        rendered[start_offset...end_offset] = replacement.b
      end
      rendered.force_encoding(original_encoding)
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
      separator = children.first&.separator || entry_member.separator
      if inline_member?(entry_member)
        insertion_point = entry_member.value_start + 1
        rendered_comment = "\"comment\"#{separator}#{encoded_comment}"
        rendered_comment = "#{rendered_comment}," unless children.empty?
        return [insertion_point, insertion_point, rendered_comment]
      end

      entry_indent = line_indent(entry_member.key_start)
      child_indent = children.empty? ? "#{entry_indent}#{indent_unit}" : line_indent(children.first.key_start)
      child_indent = "#{entry_indent}#{indent_unit}" unless child_indent.match?(/\A\s*\z/)
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

    def inline_member?(member)
      !line_indent(member.key_start).match?(/\A[ \t]*\z/)
    end

    def indent_unit
      @indent_unit ||= begin
        strings_indent = line_indent(@strings_member.key_start)
        block_entry = @entry_members.find { |member| !inline_member?(member) }
        entry_indent = line_indent(block_entry&.key_start || @strings_member.key_start)
        difference = entry_indent.delete_prefix(strings_indent)
        difference.empty? || !difference.match?(/\A[ \t]*\z/) ? '  ' : difference
      end
    end

    def newline
      @newline ||= @content.include?("\r\n") ? "\r\n" : "\n"
    end

    def line_indent(offset)
      following_line = @line_starts.bsearch_index { |line_start| line_start > offset }
      line_start = following_line ? @line_starts.fetch(following_line - 1) : @line_starts.last
      byte_slice(line_start, offset)
    end

    def line_number(offset)
      @line_starts.bsearch_index { |line_start| line_start > offset } || @line_starts.length
    end

    def object_members(object_start)
      raise TypeError, "expected object at byte #{object_start}" unless byte_at(object_start) == BYTE[:open_object]

      members = []
      cursor = skip_whitespace(object_start + 1)
      return members if byte_at(cursor) == BYTE[:close_object]

      loop do
        key_start = cursor
        key_end = string_end(key_start)
        key = JSON.parse(byte_slice(key_start, key_end))
        cursor = skip_whitespace(key_end)
        raise TypeError, "expected ':' at byte #{cursor}" unless byte_at(cursor) == BYTE[:colon]

        cursor = skip_whitespace(cursor + 1)
        value_start = cursor
        value_end = value_end(value_start)
        members << Member.new(
          key: key,
          key_start: key_start,
          key_end: key_end,
          value_start: value_start,
          value_end: value_end,
          separator: byte_slice(key_end, value_start)
        )
        cursor = skip_whitespace(value_end)
        break if byte_at(cursor) == BYTE[:close_object]

        raise TypeError, "expected ',' at byte #{cursor}" unless byte_at(cursor) == BYTE[:comma]

        cursor = skip_whitespace(cursor + 1)
      end

      members
    end

    def value_end(start_offset)
      case byte_at(start_offset)
      when BYTE[:quote]
        string_end(start_offset)
      when BYTE[:open_object]
        collection_end(start_offset, BYTE[:open_object], BYTE[:close_object])
      when BYTE[:open_array]
        collection_end(start_offset, BYTE[:open_array], BYTE[:close_array])
      else
        primitive_end(start_offset)
      end
    end

    def string_end(start_offset)
      cursor = start_offset + 1
      escaped = false
      while cursor < @content.bytesize
        byte = byte_at(cursor)
        if escaped
          escaped = false
        elsif byte == BYTE[:backslash]
          escaped = true
        elsif byte == BYTE[:quote]
          return cursor + 1
        end
        cursor += 1
      end
      raise TypeError, "unterminated string at byte #{start_offset}"
    end

    def collection_end(start_offset, opening, closing)
      depth = 0
      cursor = start_offset
      while cursor < @content.bytesize
        byte = byte_at(cursor)
        case byte
        when BYTE[:quote]
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
      cursor += 1 while cursor < @content.bytesize && !PRIMITIVE_TERMINATOR_BYTES.include?(byte_at(cursor))
      cursor
    end

    def skip_whitespace(offset)
      cursor = offset
      cursor += 1 while cursor < @content.bytesize && JSON_WHITESPACE_BYTES.include?(byte_at(cursor))
      cursor
    end

    def byte_at(offset)
      @content.getbyte(offset)
    end

    def byte_slice(start_offset, end_offset)
      @content.byteslice(start_offset...end_offset)
    end
  end
end
