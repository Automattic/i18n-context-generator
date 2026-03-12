# frozen_string_literal: true

module Txcontext
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

        lines = File.readlines(source_path, encoding: 'UTF-8')
        results_by_key = build_results_lookup(results)

        output_lines = []
        i = 0

        while i < lines.length
          line = lines[i]

          # Only write comments on <string> elements, not <plurals> or <string-array>.
          # Plural/array parent comments would use a single child's description which
          # is misleading for the resource as a whole.
          if (match = line.match(%r{^(\s*)<string\s+name="([^"]+)"[^>]*>.*</string>\s*$}))
            indent = match[1]
            key = match[2]
            result = results_by_key[key]

            insert_context_comment(output_lines, indent, result.description) if result&.description && !skip_description?(result.description)
          end

          output_lines << line
          i += 1
        end

        File.write(source_path, output_lines.join)
      end

      private

      # Build a lookup that maps base resource names to results.
      # For plural keys like "post_likes_count:one", maps "post_likes_count" to a result.
      # For array keys like "days_of_week[0]", maps "days_of_week" to a result.
      # Standard string keys map directly.
      # Results are sorted by key first so the lookup is deterministic regardless
      # of concurrent execution order.
      def build_results_lookup(results)
        lookup = {}
        results.sort_by(&:key).each do |r|
          base = r.key.sub(/:[a-z]+$/, '').sub(/\[\d+\]$/, '')
          lookup[base] ||= r
          lookup[r.key] ||= r
        end
        lookup
      end

      def insert_context_comment(output_lines, indent, description)
        context_text = "#{@context_prefix}#{escape_comment(description)}"

        if output_lines.any? && output_lines.last.match?(/^\s*<!--.*-->\s*$/)
          existing_match = output_lines.last.match(/^\s*<!--\s*(.*?)\s*-->\s*$/)
          existing_comment = existing_match ? existing_match[1] : ''

          if txcontext_managed?(existing_comment)
            # Update existing txcontext comment
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

      # A comment is txcontext-managed if it contains the configured context prefix.
      # When prefix is empty, we cannot distinguish managed from unmanaged comments,
      # so we always treat the preceding comment as replaceable — the user accepted
      # this trade-off by choosing an empty prefix.
      def txcontext_managed?(comment)
        @context_prefix.empty? || comment.include?(@context_prefix)
      end

      def build_comment(existing_comment, context_text)
        if existing_comment.nil? || existing_comment.empty? || @context_mode == 'replace'
          context_text
        elsif !@context_prefix.empty? && existing_comment.include?(@context_prefix)
          # Replace existing context line (idempotent update)
          existing_comment.gsub(/#{Regexp.escape(@context_prefix)}[^\n]*/, context_text)
        else
          # Append context to existing comment
          "#{existing_comment} #{context_text}"
        end
      end

      def escape_comment(text)
        # Remove any existing comment markers and newlines
        text
          .gsub('--', '- -') # Double dash not allowed in XML comments
          .gsub("\n", ' ')
          .strip
      end
    end
  end
end
