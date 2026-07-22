# frozen_string_literal: true

require 'find'

module I18nContextGenerator
  # Validates that a run targets a single mobile platform after applying ignore rules.
  class PlatformValidator
    def initialize(config)
      @config = config
      @ignore_patterns = @config.ignore_patterns.map { |pattern| glob_to_regex(pattern) }
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
      basename = File.basename(path).downcase
      ext = File.extname(path).downcase

      case ext
      when '.strings'
        [:ios]
      when '.xml'
        basename == 'strings.xml' || path.include?('/res/values') ? [:android] : []
      else
        []
      end
    end

    def source_platforms_for_path(path)
      return [] unless File.exist?(path)
      return [] if File.directory?(path) && ignored_source_file?(path, directory: true)

      if File.file?(path)
        platform = source_platform_for_file(path)
        return platform ? [platform] : []
      end

      platforms = []

      Find.find(path) do |file|
        if File.directory?(file)
          next unless file != path && ignored_source_file?(file, directory: true)

          Find.prune
        end

        next if ignored_source_file?(file)

        platform = source_platform_for_file(file)
        next unless platform
        next if platforms.include?(platform)

        platforms << platform
        break if platforms.size == 2
      end

      platforms
    end

    def source_platform_for_file(path)
      case File.extname(path).downcase
      when '.swift', '.m', '.mm'
        :ios
      when '.kt', '.java'
        :android
      when '.xml'
        :android if path.split(File::SEPARATOR).include?('res')
      end
    end

    def validate_code_write_back!(platform)
      return unless @config.write_back_to_code

      raise Error, 'write_back_to_code is supported only for iOS Swift sources' unless platform == :ios
      return if @config.source_paths.any? { |path| contains_writable_swift_source?(path) }

      raise Error, 'write_back_to_code requires at least one non-ignored Swift source file'
    end

    def contains_writable_swift_source?(path)
      return path.end_with?('.swift') && !ignored_source_file?(path) if File.file?(path)
      return false unless File.directory?(path)
      return false if ignored_source_file?(path, directory: true)

      Find.find(path) do |file|
        if File.directory?(file)
          next unless file != path && ignored_source_file?(file, directory: true)

          Find.prune
        end

        return true if file.end_with?('.swift') && !ignored_source_file?(file)
      end
      false
    end

    def ignored_source_file?(path, directory: false)
      @ignore_patterns.any? do |pattern|
        candidates = [path]
        candidates << "#{path}/" if directory && !path.end_with?('/')
        @config.source_paths.each do |root|
          prefix = root.end_with?('/') ? root : "#{root}/"
          next unless path.start_with?(prefix)

          relative_path = path.delete_prefix(prefix)
          candidates << relative_path
          candidates << "#{relative_path}/" if directory && !relative_path.end_with?('/')
        end
        candidates.any? { |candidate| pattern.match?(candidate) }
      end
    end

    def glob_to_regex(glob_pattern)
      regex_str = Regexp.escape(glob_pattern)
                        .gsub('\*\*/', '(.*/)?')
                        .gsub('\*\*', '.*')
                        .gsub('\*', '[^/]*')
                        .gsub('\?', '.')
      Regexp.new("(?:^|/)#{regex_str}(?:$|/)")
    end
  end
end
