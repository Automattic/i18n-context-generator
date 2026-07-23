# frozen_string_literal: true

module I18nContextGenerator
  class Config
    # Built-in source exclusions and their additive merge policy.
    module Defaults
      def default_ignore_patterns
        [
          '**/node_modules/**',
          '**/vendor/**',
          '**/.git/**',
          '**/build/**',
          '**/dist/**',
          '**/*.min.js',
          '**/*.test.*',
          '**/*.spec.*',
          '**/Pods/**',
          '**/Carthage/**',
          '**/.build/**',
          '**/DerivedData/**',
          '**/*Tests.swift',
          '**/*Tests.kt',
          '**/*Test.java',
          '**/*Test.kt'
        ]
      end

      def merge_ignore_patterns(patterns)
        return patterns unless patterns.is_a?(Array)

        (default_ignore_patterns + patterns).compact.uniq
      end
    end
  end
end
