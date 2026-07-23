# frozen_string_literal: true

module I18nContextGenerator
  # Shared ownership and merge rules for context generated into destination
  # comments. Writers remain responsible for destination-specific escaping.
  module GeneratedComment
    module_function

    def merge(existing:, generated:, prefix:, mode:, separator:)
      return generated if existing.nil? || existing.empty? || mode.to_s == 'replace'

      if prefix.empty?
        return existing if existing.include?(generated)

        return "#{existing}#{separator}#{generated}"
      end

      return replace_managed(existing, generated, prefix) if managed?(existing, prefix: prefix)

      "#{existing}#{separator}#{generated}"
    end

    def managed?(comment, prefix:)
      prefix.empty? || comment.to_s.include?(prefix)
    end

    def replace_managed(existing, generated, prefix)
      existing.gsub(/#{Regexp.escape(prefix)}[^\n]*/) { generated }
    end
    private_class_method :replace_managed
  end
end
