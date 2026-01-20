# frozen_string_literal: true

module Txcontext
  module Writers
    # Writer that updates comment: parameters in Swift localization calls
    # Supports NSLocalizedString, String(localized:), Text(), and custom functions
    class SwiftWriter
      # Default patterns for Swift localization functions
      # Each pattern should capture: (prefix)(key)(middle)(comment_value)(suffix)
      DEFAULT_FUNCTIONS = %w[
        NSLocalizedString
        String(localized:
        Text(
      ].freeze

      def initialize(functions: nil, context_prefix: "Context: ", context_mode: "replace")
        @functions = functions || DEFAULT_FUNCTIONS
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      # Write context back to all Swift files that contain the keys
      # @param results [Array] extraction results with key and description
      # @param source_paths [Array<String>] paths to search for Swift files
      def write_to_source_files(results, source_paths)
        results_by_key = results.to_h { |r| [r.key, r] }

        source_paths.each do |source_path|
          swift_files = find_swift_files(source_path)

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
          next unless result&.description
          next if skip_description?(result.description)

          new_content = update_comment_for_key(content, key, result.description)
          if new_content != content
            content = new_content
            updated = true
          end
        end

        if updated && content != original_content
          File.write(path, content)
          true
        else
          false
        end
      end

      private

      def find_swift_files(path)
        if File.file?(path) && path.end_with?(".swift")
          [path]
        elsif File.directory?(path)
          Dir.glob(File.join(path, "**", "*.swift"))
        else
          []
        end
      end

      def skip_description?(description)
        description.include?("No usage found") || description.include?("Processing failed")
      end

      # Update comment for a specific key in the content
      def update_comment_for_key(content, key, description)
        escaped_key = Regexp.escape(key)

        @functions.each do |func|
          # Build pattern based on function type
          pattern = build_pattern_for_function(func, escaped_key)
          next unless pattern

          # Try to match and replace
          content = content.gsub(pattern) do |match|
            update_match(match, func, key, description)
          end
        end

        content
      end

      def build_pattern_for_function(func, escaped_key)
        case func
        when "NSLocalizedString"
          # NSLocalizedString("key", comment: "...")
          # NSLocalizedString("key", value: "...", comment: "...")
          # NSLocalizedString("key", tableName: "...", comment: "...")
          /NSLocalizedString\(\s*"#{escaped_key}"[^)]*comment:\s*"[^"]*"[^)]*\)/m
        when "String(localized:"
          # String(localized: "key", comment: "...")
          /String\(\s*localized:\s*"#{escaped_key}"[^)]*comment:\s*"[^"]*"[^)]*\)/m
        when "Text("
          # Text("key", comment: "...")
          # Text(LocalizedStringKey("key"), comment: "...")
          /Text\([^)]*"#{escaped_key}"[^)]*comment:\s*"[^"]*"[^)]*\)/m
        else
          # Custom function - assume pattern like: func("key", ..., comment: "...")
          escaped_func = Regexp.escape(func)
          /#{escaped_func}\([^)]*"#{escaped_key}"[^)]*comment:\s*"[^"]*"[^)]*\)/m
        end
      end

      def update_match(match, func, key, new_comment)
        # Replace the comment value while preserving the rest of the call
        match.gsub(/comment:\s*"([^"]*)"/) do |comment_match|
          existing_comment = Regexp.last_match(1)
          final_comment = build_final_comment(existing_comment, new_comment)
          "comment: \"#{escape_swift_string(final_comment)}\""
        end
      end

      def build_final_comment(existing_comment, new_context)
        context_line = "#{@context_prefix}#{new_context}"

        if existing_comment.nil? || existing_comment.empty?
          context_line
        elsif @context_mode == "replace"
          # Replace entire comment
          context_line
        elsif !@context_prefix.empty? && existing_comment.include?(@context_prefix)
          # Update existing context line (idempotent)
          existing_comment.gsub(/#{Regexp.escape(@context_prefix)}[^\n]*/, context_line)
        else
          # Append context to existing comment
          "#{existing_comment} #{context_line}"
        end
      end

      def escape_swift_string(str)
        str.gsub("\\", "\\\\")
           .gsub('"', '\\"')
           .gsub("\n", "\\n")
           .gsub("\t", "\\t")
      end
    end
  end
end
