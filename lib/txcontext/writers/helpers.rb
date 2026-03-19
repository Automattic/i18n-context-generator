# frozen_string_literal: true

module Txcontext
  module Writers
    # Shared utilities for writer classes (description filtering, file discovery).
    module Helpers
      def skip_description?(description)
        description.include?('No usage found') || description.include?('Processing failed')
      end

      def writable_result?(result)
        return false unless result&.description
        return false unless result.error.nil?
        return false if result.description.strip.empty?

        !skip_description?(result.description)
      end

      def result_matches_source_path?(result, source_path)
        return true unless result.respond_to?(:source_file) && result.source_file

        File.expand_path(result.source_file) == File.expand_path(source_path)
      end

      def find_swift_files(path, ignore_patterns: [])
        files = if File.file?(path) && path.end_with?('.swift')
                  [path]
                elsif File.directory?(path)
                  Dir.glob(File.join(path, '**', '*.swift'))
                else
                  []
                end

        filter_ignored_paths(files, ignore_patterns)
      end

      private

      def filter_ignored_paths(paths, ignore_patterns)
        compiled_patterns = ignore_patterns.map { |pattern| glob_to_regex(pattern) }
        paths.reject { |path| ignored_path?(path, compiled_patterns) }.sort
      end

      def ignored_path?(path, compiled_patterns)
        compiled_patterns.any? { |pattern| pattern.match?(path) }
      end

      def glob_to_regex(glob_pattern)
        regex_str = Regexp.escape(glob_pattern)
                          .gsub('\*\*/', '(.*/)?')
                          .gsub('\*\*', '.*')
                          .gsub('\*', '[^/]*')
                          .gsub('\?', '.')
        Regexp.new("(?:^|/)#{regex_str}(?:$|/)")
      end
    end
  end
end
