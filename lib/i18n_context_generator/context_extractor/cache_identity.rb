# frozen_string_literal: true

module I18nContextGenerator
  class ContextExtractor
    # Builds a stable cache identity from every input that can shape the prompt.
    module CacheIdentity
      private

      def cache_context(entry, matches, comment)
        JSON.generate(
          matches: sorted_cache_matches(matches),
          comment: comment,
          provider: @config.provider,
          resolved_model: resolved_model,
          endpoint: @config.endpoint,
          prompt: cache_prompt_settings,
          source_discovery: cache_source_discovery(entry)
        )
      end

      def sorted_cache_matches(matches)
        cache_matches = matches.map do |match|
          {
            file: match.file,
            line: match.line,
            match_line: match.match_line,
            enclosing_scope: match.enclosing_scope,
            context: match.context
          }
        end
        cache_matches.sort_by { |match| [match[:file].to_s, match[:line].to_i, match[:match_line].to_s] }
      end

      def cache_prompt_settings
        {
          include_file_paths: @config.include_file_paths,
          redact_prompts: @config.redact_prompts,
          max_prompt_chars: @config.max_prompt_chars
        }
      end

      def cache_source_discovery(entry)
        {
          source_file: entry.source_file,
          source_location: entry.metadata&.dig(:source_location),
          source_locations: entry.metadata&.dig(:source_locations),
          source_location_groups: entry.metadata&.dig(:source_location_groups)
        }
      end
    end
  end
end
