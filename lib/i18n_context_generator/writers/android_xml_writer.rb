# frozen_string_literal: true

require_relative '../android_resource'
require_relative '../generated_comment'

module I18nContextGenerator
  module Writers
    # Writer that updates Android strings.xml files with context comments
    # Uses line-by-line approach to preserve original formatting
    class AndroidXmlWriter
      include Helpers

      def initialize(context_prefix: 'Context: ', context_mode: 'replace')
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      def write(results, source_path)
        return unless File.exist?(source_path)

        original_content = File.binread(source_path)
        lines = File.readlines(source_path, encoding: 'UTF-8')
        results_by_key = build_results_lookup(results, source_path)
        return false unless results_by_key.values.any? { |result| writable_result?(result) }

        output_lines = []
        i = 0

        while i < lines.length
          line = lines[i]

          # Only write comments on <string> elements, not <plurals> or <string-array>.
          # Plural/array parent comments would use a single child's description which
          # is misleading for the resource as a whole.
          # Match the complete opening tag so attribute order, quote style, and
          # multiline attributes do not affect write-back.
          if (element = string_element_at(lines, i))
            indent = element[:indent]
            key = element[:key]
            result = results_by_key[key]

            insert_context_comment(output_lines, indent, result.description) if writable_result?(result)
          end

          output_lines << line
          i += 1
        end

        rendered = output_lines.join
        return false if rendered == original_content

        AtomicFile.replace(source_path, rendered) do |candidate_path|
          REXML::Document.new(File.read(candidate_path, encoding: 'UTF-8'))
        end
        true
      end

      private

      def string_element_at(lines, index)
        start_match = lines[index].match(/^(\s*)<string(?=\s|>)/)
        return unless start_match

        opening_tag_lines = []
        lines[index..].each do |line|
          opening_tag_lines << line
          break if line.include?('>')
        end
        opening_tag = opening_tag_lines.join
        opening_tag = opening_tag.split('>', 2).first
        name_match = opening_tag.match(/\bname\s*=\s*(["'])(.*?)\1/m)
        return unless name_match

        { indent: start_match[1], key: name_match[2] }
      end

      # Build a lookup that maps base resource names to results.
      # For plural keys like "post_likes_count:one", maps "post_likes_count" to a result.
      # For array keys like "days_of_week[0]", maps "days_of_week" to a result.
      # Standard string keys map directly.
      # Results are sorted by key first so the lookup is deterministic regardless
      # of concurrent execution order.
      def build_results_lookup(results, source_path = nil)
        lookup = {}
        results.sort_by(&:key).each do |r|
          next if source_path && !result_matches_source_path?(r, source_path)

          base = AndroidResource.base_key(r.key)
          lookup[base] ||= r
          lookup[r.key] ||= r
        end
        lookup
      end

      def insert_context_comment(output_lines, indent, description)
        context_text = escape_comment("#{@context_prefix}#{description}")

        if output_lines.any? && output_lines.last.match?(/^\s*<!--.*-->\s*$/)
          existing_match = output_lines.last.match(/^\s*<!--\s*(.*?)\s*-->\s*$/)
          existing_comment = existing_match ? existing_match[1] : ''

          if managed_comment?(existing_comment)
            # Update existing context comment
            output_lines.pop
            new_comment = build_comment(existing_comment, context_text)
            output_lines << "#{indent}<!-- #{new_comment} -->\n"
          else
            # Preceding comment is not ours (e.g. a section header) — leave it, insert new
            output_lines << "#{indent}<!-- #{context_text} -->\n"
          end
        else
          output_lines << "#{indent}<!-- #{context_text} -->\n"
        end
      end

      # A comment is managed by us if it contains the configured context prefix.
      # When prefix is empty, we cannot distinguish managed from unmanaged comments,
      # so we always treat the preceding comment as replaceable — the user accepted
      # this trade-off by choosing an empty prefix.
      def managed_comment?(comment)
        GeneratedComment.managed?(comment, prefix: escaped_context_prefix)
      end

      def build_comment(existing_comment, context_text)
        GeneratedComment.merge(
          existing: existing_comment,
          generated: context_text,
          prefix: escaped_context_prefix,
          mode: @context_mode,
          separator: ' '
        )
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text
          .gsub('--', '- -') # Double dash not allowed in XML comments
          .gsub("\n", ' ')
          .strip
      end

      def escaped_context_prefix
        escape_comment(@context_prefix)
      end
    end
  end
end
