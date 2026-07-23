# frozen_string_literal: true

module I18nContextGenerator
  # Owns source and translation file-type classification. Header files remain
  # searchable for iOS runs but are deliberately not platform evidence because
  # generic C headers also occur in Android projects.
  module FileClassifier
    IOS_SOURCE_EXTENSIONS = %w[.swift .m .mm].freeze
    IOS_SEARCH_EXTENSIONS = (IOS_SOURCE_EXTENSIONS + ['.h']).freeze
    ANDROID_SOURCE_EXTENSIONS = %w[.kt .java].freeze
    SEARCH_EXTENSIONS = {
      ios: IOS_SEARCH_EXTENSIONS,
      android: (ANDROID_SOURCE_EXTENSIONS + ['.xml']).freeze,
      unknown: (IOS_SEARCH_EXTENSIONS + ANDROID_SOURCE_EXTENSIONS + ['.xml']).freeze
    }.freeze

    module_function

    def source_platform(path)
      extension = File.extname(path).downcase
      return :ios if IOS_SOURCE_EXTENSIONS.include?(extension)
      return :android if ANDROID_SOURCE_EXTENSIONS.include?(extension)

      :android if android_source_xml?(path)
    end

    def searchable_platform(path, platform_hint: nil)
      return :ios if File.extname(path).downcase == '.h'
      return :android if File.extname(path).downcase == '.xml' && platform_hint&.to_sym == :android

      source_platform(path)
    end

    def searchable_source?(path, platform: :unknown)
      extensions = SEARCH_EXTENSIONS.fetch(platform.to_sym, SEARCH_EXTENSIONS[:unknown])
      return false unless extensions.include?(File.extname(path).downcase)
      return platform.to_sym == :android || android_source_xml?(path) if File.extname(path).downcase == '.xml'

      true
    end

    def translation_platform(path)
      case File.extname(path).downcase
      when '.strings', '.xcstrings' then :ios
      when '.xml' then :android if android_translation_file?(path)
      end
    end

    def android_resource_xml?(path)
      File.extname(path).downcase == '.xml' && path_components(path).include?('res')
    end

    def android_source_xml?(path)
      android_resource_xml?(path) || File.basename(path).casecmp('AndroidManifest.xml').zero?
    end

    def android_translation_file?(path)
      return false unless File.extname(path).downcase == '.xml'
      return true if File.basename(path).casecmp('strings.xml').zero?

      path_components(path).each_cons(2).any? { |first, second| first == 'res' && second.start_with?('values') }
    end

    def swift_source?(path)
      File.extname(path).downcase == '.swift'
    end

    def path_components(path)
      path.to_s.tr('\\', '/').split('/').reject(&:empty?)
    end
  end
end
