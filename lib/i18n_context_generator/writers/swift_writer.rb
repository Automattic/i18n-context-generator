# frozen_string_literal: true

require_relative '../generated_comment'
require_relative '../localization_syntax'

module I18nContextGenerator
  module Writers
    # Writer that updates comment: parameters in Swift localization calls
    # Supports NSLocalizedString, String(localized:), Text(), and custom functions
    class SwiftWriter
      include Helpers

      COMMENT_ARGUMENT_PATTERN = /comment:\s*"((?:\\.|[^"\\])*)"/
      private_constant :COMMENT_ARGUMENT_PATTERN

      def initialize(functions: nil, context_prefix: 'Context: ', context_mode: 'replace')
        @localization_syntax = LocalizationSyntax.new(swift_functions: functions)
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      # Write context back to all Swift files that contain the keys
      # @param results [Array] extraction results with key and description
      # @param source_paths [Array<String>] paths to search for Swift files
      def write_to_source_files(results, source_paths, ignore_patterns: [])
        results_by_key = results.to_h { |r| [r.key, r] }

        source_paths.each do |source_path|
          swift_files = find_swift_files(source_path, ignore_patterns: ignore_patterns)

          swift_files.each do |swift_file|
            update_file(swift_file, results_by_key)
          end
        end
      end

      # Update a single Swift file with context comments
      # @param path [String] path to Swift file
      # @param results_by_key [Hash] results keyed by translation key
      def update_file(path, results_by_key)
        return unless File.exist?(path)

        content = File.read(path)
        original_content = content.dup
        updated = false

        results_by_key.each do |key, result|
          next unless writable_result?(result)

          new_content = update_comment_for_key(content, key, result.description)
          if new_content != content
            content = new_content
            updated = true
          end
        end

        if updated && content != original_content
          AtomicFile.replace(path, content)
          true
        else
          false
        end
      end

      private

      # Update comment for a specific key in the content
      def update_comment_for_key(content, key, description)
        @localization_syntax.swift_writer_patterns(key).each do |pattern|
          # Try to match and replace
          content = content.gsub(pattern) do |match|
            update_match(match, description)
          end
        end

        content
      end

      def update_match(match, new_comment)
        # Replace the comment value while preserving the rest of the call
        match.gsub(COMMENT_ARGUMENT_PATTERN) do |_comment_match|
          existing_comment = unescape_swift_string(Regexp.last_match(1))
          final_comment = build_final_comment(existing_comment, new_comment)
          "comment: \"#{escape_swift_string(final_comment)}\""
        end
      end

      def build_final_comment(existing_comment, new_context)
        context_line = "#{@context_prefix}#{new_context}"
        GeneratedComment.merge(
          existing: existing_comment,
          generated: context_line,
          prefix: @context_prefix,
          mode: @context_mode,
          separator: ' '
        )
      end

      def escape_swift_string(str)
        str.gsub('\\', '\\\\')
           .gsub('"', '\\"')
           .gsub("\r", '\\r')
           .gsub("\n", '\\n')
           .gsub("\t", '\\t')
      end

      def unescape_swift_string(str)
        escape_map = {
          '"' => '"',
          '\\' => '\\',
          'n' => "\n",
          'r' => "\r",
          't' => "\t"
        }

        str.gsub(/\\(["\\nrt])/) do
          escape_map.fetch(Regexp.last_match(1))
        end
      end
    end
  end
end
