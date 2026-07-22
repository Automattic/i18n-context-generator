# frozen_string_literal: true

require_relative 'path_policy'
require_relative 'file_classifier'

module I18nContextGenerator
  # Validates that a run targets a single mobile platform after applying ignore rules.
  class PlatformValidator
    def initialize(config)
      @config = config
      @path_policy = PathPolicy.new(ignore_patterns: @config.ignore_patterns, roots: @config.source_paths)
    end

    def validate!
      platforms = (@config.translations.flat_map { |path| translation_platforms_for_path(path) } +
        @config.source_paths.flat_map { |path| source_platforms_for_path(path) }).uniq

      raise Error, 'Mixed iOS and Android runs are not supported. Split them into separate invocations or config files.' if platforms.size > 1

      detected_platform = platforms.first
      requested_platform = @config.platform&.to_sym
      raise Error, "Configured platform #{requested_platform} conflicts with detected #{detected_platform} inputs" if requested_platform && detected_platform && requested_platform != detected_platform

      resolved_platform = requested_platform || detected_platform || :unknown
      validate_code_write_back!(resolved_platform)

      resolved_platform
    end

    private

    def translation_platforms_for_path(path)
      platform = FileClassifier.translation_platform(path)
      platform ? [platform] : []
    end

    def source_platforms_for_path(path)
      return [] unless File.exist?(path)

      platforms = []
      @path_policy.each_file(path) do |file|
        platform = FileClassifier.source_platform(file)
        next unless platform
        next if platforms.include?(platform)

        platforms << platform
        break if platforms.size == 2
      end

      platforms
    end

    def validate_code_write_back!(platform)
      return unless @config.write_back_to_code

      raise Error, 'write_back_to_code is supported only for iOS Swift sources' unless platform == :ios
      return if @config.source_paths.any? { |path| contains_writable_swift_source?(path) }

      raise Error, 'write_back_to_code requires at least one non-ignored Swift source file'
    end

    def contains_writable_swift_source?(path)
      @path_policy.each_file(path).any? { |file| FileClassifier.swift_source?(file) }
    end
  end
end
