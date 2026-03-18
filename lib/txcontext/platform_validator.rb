# frozen_string_literal: true

require 'find'

module Txcontext
  # Validates that a run targets a single mobile platform after applying ignore rules.
  class PlatformValidator
    def initialize(config)
      @config = config
      @ignore_patterns = @config.ignore_patterns.map { |pattern| glob_to_regex(pattern) }
    end

    def validate!
      platforms = (@config.translations.flat_map { |path| translation_platforms_for_path(path) } +
        @config.source_paths.flat_map { |path| source_platforms_for_path(path) }).uniq

      return if platforms.size <= 1

      raise Error, 'Mixed iOS and Android runs are not supported. Split them into separate invocations or config files.'
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

      if File.file?(path)
        platform = source_platform_for_file(path)
        return platform ? [platform] : []
      end

      platforms = []

      Find.find(path) do |file|
        next unless File.file?(file)
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
      when '.swift', '.m', '.mm', '.h'
        :ios
      when '.kt', '.java'
        :android
      end
    end

    def ignored_source_file?(path)
      @ignore_patterns.any? do |pattern|
        candidates = [path]
        @config.source_paths.each do |root|
          prefix = root.end_with?('/') ? root : "#{root}/"
          candidates << path.delete_prefix(prefix) if path.start_with?(prefix)
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
