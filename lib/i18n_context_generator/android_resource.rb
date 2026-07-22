# frozen_string_literal: true

module I18nContextGenerator
  # Canonical Android string-resource identity and source-span indexing.
  module AndroidResource
    TAG_TYPES = {
      'string' => :string,
      'plurals' => :plural,
      'string-array' => :array
    }.freeze
    TYPE_TAGS = TAG_TYPES.invert.freeze
    RESOURCE_OPEN_PATTERN = /<(?<tag>string-array|plurals|string)\b(?<attributes>[^>]*?)>/m
    ITEM_OPEN_PATTERN = /<item\b(?<attributes>[^>]*?)>/m

    Span = Data.define(:key, :base_key, :resource_type, :start_line, :end_line, :parent_start_line, :parent_end_line) do
      def line_span
        start_line..end_line
      end

      def parent_line_span
        parent_start_line..parent_end_line
      end

      def cover?(line_number)
        line_span.cover?(line_number)
      end
    end

    # Query object shared by parsers and diff/location consumers.
    class Index
      attr_reader :entry_spans, :resource_spans

      def initialize(entry_spans:, resource_spans:)
        @entry_spans = entry_spans.freeze
        @resource_spans = resource_spans.freeze
        @entries_by_key = @entry_spans.group_by(&:key)
      end

      def span_for(key)
        @entries_by_key[key]&.first
      end

      def base_key_at(line_number)
        @resource_spans.find { |span| span.cover?(line_number) }&.base_key
      end

      def member_at(line_number, parent:)
        matches = @entry_spans.select do |span|
          span.base_key == parent && span.resource_type != :string && span.cover?(line_number)
        end
        keys = matches.map(&:key).uniq
        keys.one? ? keys.first : nil
      end
    end

    module_function

    def base_key(key)
      key.to_s.sub(/:[a-z]+$/, '').sub(/\[\d+\]$/, '')
    end

    def type_for(key, explicit: nil)
      return explicit.to_sym if explicit
      return :plural if key.to_s.match?(/:[a-z]+$/)
      return :array if key.to_s.match?(/\[\d+\]$/)

      :string
    end

    def composite_key(name, type:, quantity: nil, index: nil)
      case type.to_sym
      when :plural then "#{name}:#{quantity}"
      when :array then "#{name}[#{index}]"
      else name
      end
    end

    def type_for_tag(tag)
      TAG_TYPES[tag]
    end

    def tag_for_type(type)
      TYPE_TAGS[type.to_sym]
    end

    def index(content)
      Scanner.new(content).index
    end

    # Internal scanner that runs after XML syntax validation. It preserves line
    # positions while masking comments and records parent plus child spans.
    class Scanner
      def initialize(content)
        @content = content
        @visible_content = mask_comments(content)
        @line_starts = [0]
        content.to_enum(:scan, /\n/).each { @line_starts << Regexp.last_match.end(0) }
      end

      def index
        entry_spans = []
        resource_spans = []
        offset = 0

        while (match = RESOURCE_OPEN_PATTERN.match(@visible_content, offset))
          resource_end, closing_start = element_end(match, match[:tag])
          span = resource_span(match, resource_end)
          if span
            resource_spans << span
            if span.resource_type == :string
              entry_spans << span
            else
              entry_spans.concat(item_spans(match.end(0), closing_start, span))
            end
          end
          offset = [resource_end, match.end(0)].max
        end

        Index.new(entry_spans: entry_spans, resource_spans: resource_spans)
      end

      private

      def resource_span(match, resource_end)
        name = attribute(match[:attributes], 'name')
        type = AndroidResource.type_for_tag(match[:tag])
        return unless name && type

        start_line = line_for(match.begin(0))
        end_line = line_for([resource_end - 1, match.begin(0)].max)
        Span.new(
          key: name,
          base_key: name,
          resource_type: type,
          start_line: start_line,
          end_line: end_line,
          parent_start_line: start_line,
          parent_end_line: end_line
        )
      end

      def item_spans(content_start, content_end, parent_span)
        spans = []
        offset = content_start
        array_index = 0

        while offset < content_end && (match = ITEM_OPEN_PATTERN.match(@visible_content, offset))
          break if match.begin(0) >= content_end

          item_end, = element_end(match, 'item', limit: content_end)
          key = item_key(match, parent_span, array_index)
          spans << child_span(key, match.begin(0), item_end, parent_span) if key
          array_index += 1 if parent_span.resource_type == :array
          offset = [item_end, match.end(0)].max
        end
        spans
      end

      def item_key(match, parent_span, array_index)
        quantity = attribute(match[:attributes], 'quantity') if parent_span.resource_type == :plural
        return if parent_span.resource_type == :plural && quantity.nil?

        AndroidResource.composite_key(
          parent_span.base_key,
          type: parent_span.resource_type,
          quantity: quantity,
          index: array_index
        )
      end

      def child_span(key, start_offset, end_offset, parent_span)
        Span.new(
          key: key,
          base_key: parent_span.base_key,
          resource_type: parent_span.resource_type,
          start_line: line_for(start_offset),
          end_line: line_for([end_offset - 1, start_offset].max),
          parent_start_line: parent_span.start_line,
          parent_end_line: parent_span.end_line
        )
      end

      def element_end(opening_match, tag, limit: @visible_content.length)
        return [opening_match.end(0), opening_match.end(0)] if opening_match[0].rstrip.end_with?('/>')

        closing = %r{</#{Regexp.escape(tag)}\s*>}.match(@visible_content, opening_match.end(0))
        return [opening_match.end(0), opening_match.end(0)] unless closing && closing.begin(0) < limit

        [closing.end(0), closing.begin(0)]
      end

      def attribute(attributes, name)
        attributes[/\b#{Regexp.escape(name)}\s*=\s*(["'])(.*?)\1/m, 2]
      end

      def line_for(offset)
        next_line = @line_starts.bsearch_index { |line_start| line_start > offset }
        next_line || @line_starts.length
      end

      def mask_comments(content)
        content
          .gsub(/<!--.*?-->/m) { |comment| comment.gsub(/[^\n]/, ' ') }
          .gsub(/<!\[CDATA\[.*?\]\]>/m) { |cdata| cdata.gsub(/[^\n]/, ' ') }
      end
    end
    private_constant :Scanner
  end
end
