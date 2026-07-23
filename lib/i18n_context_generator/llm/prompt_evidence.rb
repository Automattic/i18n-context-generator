# frozen_string_literal: true

module I18nContextGenerator
  module LLM
    # Converts application and supplemental inputs into prompt-safe evidence records.
    module PromptEvidence
      private

      def detect_platform(matches)
        return 'mobile' if matches.empty?

        platforms = matches.filter_map { |match| FileClassifier.searchable_platform(match.file) }

        if platforms.include?(:ios)
          'iOS'
        elsif platforms.include?(:android)
          'Android'
        else
          'mobile'
        end
      end

      def prompt_matches(matches, include_file_paths:, redact_prompts:)
        matches.map do |match|
          location = include_file_paths ? match.file : File.basename(match.file)
          {
            location: sanitized_prompt_value(location, redact: redact_prompts),
            line: match.line,
            enclosing_scope: sanitized_prompt_value(match.enclosing_scope, redact: redact_prompts),
            matched_line: sanitized_prompt_value(match.match_line, redact: redact_prompts),
            context: sanitized_prompt_value(match.context, redact: redact_prompts)
          }.compact
        end
      end

      def prompt_context_sources(sources, redact_prompts:)
        sources.map do |source|
          {
            kind: sanitized_prompt_value(source.kind, redact: redact_prompts),
            name: sanitized_prompt_value(source.name, redact: redact_prompts),
            content: sanitized_prompt_value(source.content, redact: redact_prompts)
          }
        end
      end
    end
  end
end
