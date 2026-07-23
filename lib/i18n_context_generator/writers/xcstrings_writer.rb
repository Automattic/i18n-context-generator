# frozen_string_literal: true

require_relative '../generated_comment'

module I18nContextGenerator
  module Writers
    # Updates developer comments in Apple string catalogs while leaving every
    # localization and extraction attribute intact.
    class XcstringsWriter
      include Helpers

      def initialize(context_prefix: 'Context: ', context_mode: 'replace')
        @context_prefix = context_prefix
        @context_mode = context_mode
      end

      def write(results, source_path)
        return unless File.exist?(source_path)

        original = File.binread(source_path)
        document = XcstringsDocument.new(original, path: source_path)
        catalog = document.catalog
        Parsers::XcstringsParser.validate_catalog!(catalog, path: source_path)
        results_by_key = results.each_with_object({}) do |result, lookup|
          next unless result_matches_source_path?(result, source_path)
          next unless writable_result?(result)

          lookup[result.key] = result
        end
        return false if results_by_key.empty?

        comments_by_key = catalog.fetch('strings').each_with_object({}) do |(key, entry), comments|
          result = results_by_key[key]
          next unless result

          comments[key] = GeneratedComment.merge(
            existing: entry['comment'],
            generated: "#{@context_prefix}#{result.description}",
            prefix: @context_prefix,
            mode: @context_mode,
            separator: "\n"
          )
        end
        rendered = document.with_comments(comments_by_key)
        return false if rendered == original

        AtomicFile.replace(source_path, rendered) do |candidate_path|
          candidate = Oj.load_file(candidate_path, mode: :strict)
          Parsers::XcstringsParser.validate_catalog!(candidate, path: candidate_path)
        end
        true
      rescue Oj::ParseError => e
        raise Error, "Failed to parse Apple string catalog #{source_path}: #{e.message}"
      end
    end
  end
end
