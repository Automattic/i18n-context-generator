# frozen_string_literal: true

require_relative '../generated_comment'

module I18nContextGenerator
  module Writers
    # Writer that updates iOS .strings files with context comments
    # Uses the dotstrings gem for proper parsing and generation
    class StringsWriter
      include Helpers

      def initialize(context_prefix: 'Context: ', context_mode: 'replace')
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      def write(results, source_path)
        return unless File.exist?(source_path)

        # Parse the existing file
        original_file = DotStrings.parse_file(source_path, strict: false)
        results_by_key = results.each_with_object({}) do |result, lookup|
          next unless result_matches_source_path?(result, source_path)

          lookup[result.key] = result
        end

        # Build new file with updated comments (DotStrings::Item is immutable)
        new_file = DotStrings::File.new

        original_file.items.each do |item|
          result = results_by_key[item.key]

          new_comment = if writable_result?(result)
                          build_comment(item.comment, result.description)
                        else
                          item.comment
                        end

          new_item = DotStrings::Item.new(
            key: item.key,
            value: item.value,
            comment: new_comment
          )
          new_file << new_item
        end

        AtomicFile.replace(source_path, new_file.to_s) do |candidate_path|
          DotStrings.parse_file(candidate_path, strict: true)
        end
      end

      private

      def build_comment(existing_comment, context_description)
        context_line = sanitize_comment("#{@context_prefix}#{context_description}")
        context_prefix = sanitize_comment(@context_prefix)
        GeneratedComment.merge(
          existing: existing_comment,
          generated: context_line,
          prefix: context_prefix,
          mode: @context_mode,
          separator: "\n"
        )
      end

      def sanitize_comment(comment)
        comment.gsub('*/', '* /')
      end
    end
  end
end
