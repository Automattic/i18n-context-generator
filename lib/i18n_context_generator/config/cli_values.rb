# frozen_string_literal: true

module I18nContextGenerator
  class Config
    # Normalizes repeatable singular CLI values while retaining explicit legacy
    # comma-list support.
    module CliValues
      def cli_path_list(values, legacy: nil)
        repeatable = Array(values).filter_map do |value|
          normalized = value.to_s.strip
          normalized unless normalized.empty?
        end
        (repeatable + split_legacy_list(legacy)).uniq
      end

      def cli_key_filters(values, legacy: nil)
        repeatable = Array(values).filter_map do |value|
          normalized = value.to_s.strip
          normalized unless normalized.empty?
        end
        repeatable + split_legacy_list(legacy)
      end

      private

      def split_legacy_list(value)
        Array(value).flat_map { |item| item.to_s.split(',') }
                    .map(&:strip)
                    .reject(&:empty?)
      end
    end
  end
end
