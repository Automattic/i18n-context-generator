# frozen_string_literal: true

module I18nContextGenerator
  class Config
    # Secret-free, versioned representation used by --print-config and clients.
    module Serialization
      def to_h
        {
          'schema_version' => @schema_version,
          'translations' => serialized_translations,
          'source' => {
            'paths' => @source_paths,
            'ignore' => @ignore_patterns
          },
          'context' => {
            'files' => @context_files
          },
          'llm' => {
            'provider' => @provider,
            'model' => @model,
            'endpoint' => @endpoint
          }.compact,
          'processing' => {
            'discovery_mode' => @discovery_mode,
            'platform' => @platform,
            'concurrency' => @concurrency,
            'context_lines' => @context_lines,
            'max_matches_per_key' => @max_matches_per_key,
            'max_prompt_chars' => @max_prompt_chars
          }.compact,
          'cache' => {
            'enabled' => !@no_cache,
            'directory' => @cache_dir
          },
          'output' => {
            'format' => @output_format,
            'path' => (@output_path unless @output_stdout),
            'stdout' => @output_stdout,
            'write_back' => @write_back,
            'write_back_to_code' => @write_back_to_code,
            'context_prefix' => @context_prefix,
            'context_mode' => @context_mode
          }.compact,
          'swift' => { 'functions' => @swift_functions },
          'privacy' => {
            'include_file_paths' => @include_file_paths,
            'include_translation_comments' => @include_translation_comments,
            'redact_prompts' => @redact_prompts
          },
          'workflow' => { 'stage' => @workflow_stage }
        }
      end

      private

      def serialized_translations
        @translations.map do |path|
          locale = @translation_locales[path]
          locale ? { 'path' => path, 'locale' => locale } : path
        end
      end
    end
  end
end
