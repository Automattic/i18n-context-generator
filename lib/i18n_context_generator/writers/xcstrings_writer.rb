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

        catalog = Oj.load_file(source_path, mode: :strict)
        Parsers::XcstringsParser.validate_catalog!(catalog, path: source_path)
        results_by_key = results.each_with_object({}) do |result, lookup|
          next unless result_matches_source_path?(result, source_path)
          next unless writable_result?(result)

          lookup[result.key] = result
        end

        catalog.fetch('strings').each do |key, entry|
          result = results_by_key[key]
          next unless result

          entry['comment'] = GeneratedComment.merge(
            existing: entry['comment'],
            generated: "#{@context_prefix}#{result.description}",
            prefix: @context_prefix,
            mode: @context_mode,
            separator: "\n"
          )
        end

        rendered = "#{Oj.dump(catalog, indent: 2, mode: :compat)}\n"
        AtomicFile.replace(source_path, rendered) do |candidate_path|
          candidate = Oj.load_file(candidate_path, mode: :strict)
          Parsers::XcstringsParser.validate_catalog!(candidate, path: candidate_path)
        end
      rescue Oj::ParseError => e
        raise Error, "Failed to parse Apple string catalog #{source_path}: #{e.message}"
      end
    end
  end
end
