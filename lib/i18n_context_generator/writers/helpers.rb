# frozen_string_literal: true

require_relative '../path_policy'
require_relative '../file_classifier'

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
        PathPolicy.new(ignore_patterns: ignore_patterns, roots: [path])
                  .files([path]) { |file| FileClassifier.swift_source?(file) }
                  .sort
      end
    end
  end
end
