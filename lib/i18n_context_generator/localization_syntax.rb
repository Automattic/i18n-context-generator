# frozen_string_literal: true

require_relative 'android_resource'

module I18nContextGenerator
  # Registry of localization call/resource syntaxes shared by source search,
  # source-first discovery, and Swift comment write-back.
  class LocalizationSyntax
    DEFAULT_SWIFT_FUNCTIONS = %w[
      NSLocalizedString
      String(localized:
      Text(
    ].freeze

    IOS_STATIC_SEARCH_BUILDERS = [
      ->(key) { "LocalizedStringKey\\s*\\(\\s*[\"']#{key}[\"']" },
      ->(key) { "LocalizedStringKey\\s*=\\s*[\"']#{key}[\"']" },
      ->(key) { "[\"']#{key}[\"']\\.localized" }
    ].freeze

    IOS_STATIC_SINGLE_LINE_DISCOVERY_PATTERNS = [
      /LocalizedStringKey\s*\(\s*["'](?<key>[^"']+)["']\s*\)/,
      /:\s*LocalizedStringKey\s*=\s*["'](?<key>[^"']+)["']/,
      /["'](?<key>[^"']+)["']\.localized\b/
    ].freeze

    IOS_STATIC_MULTILINE_DISCOVERY_PATTERNS = [
      /Text\s*\(\s*LocalizedStringKey\s*\(\s*["'](?<key>[^"']+)["']\s*\)\s*\)/
    ].freeze

    ANDROID_DISCOVERY_PATTERNS = {
      string: %r{R\.string\.(\w+)\b|@string/([\w.]+)\b|[(\s,=]string\.(\w+)\b}x,
      plural: %r{R\.plurals\.(\w+)\b|@plurals/([\w.]+)\b|[(\s,=]plurals\.(\w+)\b}x,
      array: %r{R\.array\.(\w+)\b|@array/([\w.]+)\b|[(\s,=]array\.(\w+)\b}x
    }.freeze

    def initialize(swift_functions: nil)
      @swift_functions = Array(swift_functions || DEFAULT_SWIFT_FUNCTIONS).map(&:strip).reject(&:empty?).uniq.freeze
    end

    attr_reader :swift_functions

    def search_patterns(key, platform:, resource_type: nil)
      strings = case platform.to_sym
                when :ios then ios_search_patterns(key)
                when :android then android_search_patterns(key, resource_type: resource_type)
                else
                  ios_search_patterns(key) + android_search_patterns(key, resource_type: resource_type) +
                  [Regexp.escape(key)]
                end
      strings.map { |pattern| Regexp.new(pattern) }
    end

    def ios_search_patterns(key)
      escaped_key = Regexp.escape(key)
      function_patterns = @swift_functions.map do |function|
        "#{swift_call_prefix(function)}\\s*@?[\"']#{escaped_key}[\"']"
      end
      function_patterns + IOS_STATIC_SEARCH_BUILDERS.map { |builder| builder.call(escaped_key) }
    end

    def android_search_patterns(key, resource_type: nil)
      base_key = AndroidResource.base_key(key)
      escaped_base = Regexp.escape(base_key)

      case AndroidResource.type_for(key, explicit: resource_type)
      when :plural then android_plural_patterns(escaped_base)
      when :array then android_array_patterns(escaped_base)
      else android_string_patterns(Regexp.escape(key))
      end
    end

    def ios_single_line_discovery_patterns
      @ios_single_line_discovery_patterns ||=
        (function_discovery_patterns(multiline: false) + IOS_STATIC_SINGLE_LINE_DISCOVERY_PATTERNS).freeze
    end

    def ios_multiline_discovery_patterns
      @ios_multiline_discovery_patterns ||=
        (function_discovery_patterns(multiline: true) + IOS_STATIC_MULTILINE_DISCOVERY_PATTERNS).freeze
    end

    def ios_call_start_patterns
      @ios_call_start_patterns ||=
        @swift_functions.map { |function| Regexp.new(swift_function_opener(function)) }.freeze
    end

    def ios_function_openers
      @ios_function_openers ||= begin
        configured = @swift_functions.flat_map do |function|
          [
            Regexp.new("#{swift_function_opener(function)}\\s*$"),
            Regexp.new("#{swift_call_prefix(function)}\\s*$")
          ]
        end
        (configured.uniq + [/LocalizedStringKey\s*\(\s*$/]).freeze
      end
    end

    def ios_wrapper_definition_pattern
      @ios_wrapper_definition_pattern ||= begin
        functions = (@swift_functions.map { |function| swift_call_prefix(function) } +
          ['LocalizedStringKey\\s*\\(']).join('|')
        /\b(static\s+)?(?:let|var)\s+(\w+)\s*=\s*(?:#{functions})/
      end
    end

    def android_discovery_patterns
      ANDROID_DISCOVERY_PATTERNS
    end

    def swift_writer_patterns(key)
      escaped_key = Regexp.escape(key)
      comment = 'comment:\\s*"(?:\\\\.|[^"\\\\])*"'

      @swift_functions.map do |function|
        Regexp.new(
          "#{swift_call_prefix(function)}[^)]*\"#{escaped_key}\"[^)]*#{comment}[^)]*\\)",
          Regexp::MULTILINE
        )
      end
    end

    private

    def function_discovery_patterns(multiline:)
      tail = multiline ? '[\\s\\S]*?' : '[^\\n]*?'
      @swift_functions.flat_map do |function|
        prefix = swift_call_prefix(function)
        [
          Regexp.new("#{prefix}\\s*@?[\"'](?<key>[^\"']+)[\"']#{tail}comment:\\s*[\"'](?<comment>(?:\\\\.|[^\"'\\\\])*)[\"']"),
          Regexp.new("#{prefix}\\s*@?[\"'](?<key>[^\"']+)[\"']")
        ]
      end
    end

    def swift_call_prefix(function)
      name, arguments = function.split('(', 2)
      prefix = "#{Regexp.escape(name.strip)}\\s*\\("
      return prefix unless arguments

      arguments = arguments.strip
      arguments.empty? ? prefix : "#{prefix}\\s*#{Regexp.escape(arguments)}"
    end

    def swift_function_opener(function)
      name = function.split('(', 2).first
      "#{Regexp.escape(name.strip)}\\s*\\("
    end

    def android_plural_patterns(key)
      [
        "R\\.plurals\\.#{key}\\b", "@plurals/#{key}\\b",
        "getQuantityString\\s*\\(\\s*R\\.plurals\\.#{key}",
        "\\.getQuantityString\\s*\\(\\s*R\\.plurals\\.#{key}",
        "pluralStringResource\\s*\\(\\s*R\\.plurals\\.#{key}",
        "[\\(\\s,=]plurals\\.#{key}\\b"
      ]
    end

    def android_array_patterns(key)
      [
        "R\\.array\\.#{key}\\b", "@array/#{key}\\b",
        "getStringArray\\s*\\(\\s*R\\.array\\.#{key}",
        "\\.getStringArray\\s*\\(\\s*R\\.array\\.#{key}",
        "resources\\.getStringArray\\s*\\(\\s*R\\.array\\.#{key}",
        "[\\(\\s,=]array\\.#{key}\\b"
      ]
    end

    def android_string_patterns(key)
      [
        "R\\.string\\.#{key}\\b", "@string/#{key}\\b",
        "getString\\s*\\(\\s*R\\.string\\.#{key}",
        "\\.getString\\s*\\(\\s*R\\.string\\.#{key}",
        "stringResource\\s*\\(\\s*R\\.string\\.#{key}",
        "[\\(\\s,=]string\\.#{key}\\b",
        "getString\\s*\\(\\s*string\\.#{key}",
        "stringResource\\s*\\(\\s*string\\.#{key}"
      ]
    end
  end
end
