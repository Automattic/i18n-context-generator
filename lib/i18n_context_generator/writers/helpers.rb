# frozen_string_literal: true

require 'find'

module I18nContextGenerator
  module Writers
    # Shared utilities for writer classes (description filtering, file discovery).
    module Helpers
      def skip_description?(description)
        description.include?('No usage found') || description.include?('Processing failed')
      end

      def writable_result?(result)
        return false unless result&.description
        return false if result.respond_to?(:actionable?) && !result.actionable?
        return false unless result.error.nil?
        return false if result.description.strip.empty?

        !skip_description?(result.description)
      end

      def result_matches_source_path?(result, source_path)
        return true unless result.respond_to?(:source_file) && result.source_file

        File.expand_path(result.source_file) == File.expand_path(source_path)
      end

      def find_swift_files(path, ignore_patterns: [])
        compiled_patterns = ignore_patterns.map { |pattern| glob_to_regex(pattern) }
        files = if File.file?(path) && path.end_with?('.swift')
                  [path]
                elsif File.directory?(path) && !ignored_path?(path, compiled_patterns, directory: true)
                  find_swift_files_in_directory(path, compiled_patterns)
                else
                  []
                end

        files.reject { |file| ignored_path?(file, compiled_patterns) }.uniq.sort
      end

      private

      def find_swift_files_in_directory(path, compiled_patterns)
        files = []
        Find.find(path) do |candidate|
          if File.directory?(candidate)
            next unless candidate != path && ignored_path?(candidate, compiled_patterns, directory: true)

            Find.prune
          end

          files << candidate if candidate.end_with?('.swift')
        end
        files
      end

      def ignored_path?(path, compiled_patterns, directory: false)
        candidates = [path]
        candidates << "#{path}/" if directory && !path.end_with?('/')
        compiled_patterns.any? { |pattern| candidates.any? { |candidate| pattern.match?(candidate) } }
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
