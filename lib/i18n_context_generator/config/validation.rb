# frozen_string_literal: true

module I18nContextGenerator
  class Config
    # Validates the fully resolved configuration before extraction starts.
    module Validation
      BOOLEAN_OPTIONS = %i[
        no_cache dry_run write_back write_back_to_code include_file_paths
        include_translation_comments redact_prompts
      ].freeze
      OPTIONAL_STRING_OPTIONS = %i[
        model output_path key_filter diff_base diff_head start_key end_key platform
      ].freeze
      TRANSLATION_DIFF_EXTENSIONS = %w[.strings .xml].freeze

      def validate!
        errors = []
        validate_collections(errors)
        validate_scalars(errors)
        validate_domains(errors)
        validate_configured_paths(errors)
        validate_output(errors)
        validate_diff_support(errors)
        validate_write_back(errors)

        raise Error, "Invalid configuration: #{errors.join('; ')}" if errors.any?

        self
      end

      private

      def validate_collections(errors)
        validate_string_array(errors, :translations, @translations)
        validate_string_array(errors, :source_paths, @source_paths, allow_empty: false)
        validate_string_array(errors, :ignore_patterns, @ignore_patterns)
        validate_string_array(errors, :swift_functions, @swift_functions)

        errors << 'source_line_filter must be a mapping' if @source_line_filter && !@source_line_filter.is_a?(Hash)
        return if @translation_locales.is_a?(Hash) && @translation_locales.all? do |path, locale|
          path.is_a?(String) && locale.is_a?(String) && !locale.strip.empty?
        end

        errors << 'translation locales must map file paths to non-empty locale names'
      end

      def validate_scalars(errors)
        validate_integer(errors, :concurrency, @concurrency, minimum: 1)
        validate_integer(errors, :context_lines, @context_lines, minimum: 0)
        validate_integer(errors, :max_matches_per_key, @max_matches_per_key, minimum: 1)

        BOOLEAN_OPTIONS.each do |name|
          value = instance_variable_get(:"@#{name}")
          errors << "#{name} must be true or false" unless [true, false].include?(value)
        end

        OPTIONAL_STRING_OPTIONS.each do |name|
          value = instance_variable_get(:"@#{name}")
          next if value.nil? || (value.is_a?(String) && !value.strip.empty?)

          errors << "#{name} must be a non-empty string"
        end
        errors << 'context_prefix must be a string' unless @context_prefix.is_a?(String)
      end

      def validate_domains(errors)
        validate_inclusion(errors, :provider, @provider, VALID_PROVIDERS)
        validate_inclusion(errors, :output_format, @output_format, VALID_OUTPUT_FORMATS)
        validate_inclusion(errors, :context_mode, @context_mode, VALID_CONTEXT_MODES)
        validate_inclusion(errors, :discovery_mode, @discovery_mode, VALID_DISCOVERY_MODES)
        validate_inclusion(errors, :platform, @platform, VALID_PLATFORMS) unless @platform.nil?
      end

      def validate_configured_paths(errors)
        if string_array?(@translations)
          @translations.each do |path|
            errors << "translation file not found: #{path}" unless File.file?(path)
          end
          validate_translation_locales(errors)
        end

        return unless string_array?(@source_paths)

        @source_paths.each do |path|
          errors << "source path not found: #{path}" unless File.exist?(path)
        end
      end

      def validate_translation_locales(errors)
        return unless @translation_locales.is_a?(Hash)

        @translation_locales.each_key do |path|
          errors << "translation locale references an unconfigured file: #{path}" unless @translations.include?(path)
          next if %w[.yml .yaml].include?(File.extname(path).downcase)

          errors << "translation locale is supported only for YAML files: #{path}"
        end
      end

      def validate_output(errors)
        return unless @output_path.is_a?(String)

        extension = File.extname(@output_path).downcase
        if !extension.empty? && !VALID_OUTPUT_EXTENSIONS.key?(extension)
          errors << "output path extension must be .csv or .json: #{@output_path}"
        elsif VALID_OUTPUT_EXTENSIONS[extension] && VALID_OUTPUT_EXTENSIONS[extension] != @output_format
          errors << "output format #{@output_format} does not match #{extension} path"
        end

        parent = File.expand_path(File.dirname(@output_path))
        if File.directory?(@output_path)
          errors << "output path is a directory: #{@output_path}"
        elsif !File.directory?(parent)
          errors << "output directory not found: #{File.dirname(@output_path)}"
        elsif !File.writable?(parent)
          errors << "output directory is not writable: #{File.dirname(@output_path)}"
        elsif File.exist?(@output_path) && !File.writable?(@output_path)
          errors << "output file is not writable: #{@output_path}"
        end
      end

      def validate_diff_support(errors)
        return unless @diff_base.is_a?(String) && translation_backed_diff?
        return unless string_array?(@translations)

        unsupported = @translations.reject do |path|
          TRANSLATION_DIFF_EXTENSIONS.include?(File.extname(path).downcase)
        end
        return if unsupported.empty?

        errors << "diff_base is not supported for translation formats: #{unsupported.join(', ')}"
      end

      def validate_write_back(errors)
        return unless @write_back

        if !string_array?(@translations) || @translations.empty?
          errors << 'write_back requires at least one translation file'
        else
          unsupported = @translations.reject { |path| supported_translation_write_back?(path) }
          errors << "write_back is not supported for: #{unsupported.join(', ')}" if unsupported.any?
        end
      end

      def validate_string_array(errors, name, value, allow_empty: true)
        return if string_array?(value) && (allow_empty || value.any?)

        requirement = allow_empty ? 'an array of non-empty strings' : 'a non-empty array of strings'
        errors << "#{name} must be #{requirement}"
      end

      def string_array?(value)
        value.is_a?(Array) && value.all? { |item| item.is_a?(String) && !item.empty? }
      end

      def validate_integer(errors, name, value, minimum:)
        return if value.is_a?(Integer) && value >= minimum

        errors << "#{name} must be an integer greater than or equal to #{minimum}"
      end

      def validate_inclusion(errors, name, value, allowed)
        return if allowed.include?(value)

        errors << "#{name} must be one of: #{allowed.join(', ')}"
      end

      def translation_backed_diff?
        @discovery_mode == 'translations' || (@discovery_mode == 'auto' && @translations&.any?)
      end

      def supported_translation_write_back?(path)
        extension = File.extname(path).downcase
        return true if extension == '.strings'

        basename = File.basename(path).downcase
        extension == '.xml' && (basename == 'strings.xml' || path.include?('/res/values'))
      end
    end
  end
end
