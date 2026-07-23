# frozen_string_literal: true

require_relative 'android_resource'
require_relative 'apple_string_literal'

module I18nContextGenerator
  # Registry of localization call/resource syntaxes shared by source search,
  # source-first discovery, and Swift comment write-back.
  class LocalizationSyntax
    DEFAULT_SWIFT_FUNCTIONS = %w[
      NSLocalizedString
      String(localized:
      Text(
      LocalizedStringResource(
    ].freeze

    IOS_STATIC_SEARCH_BUILDERS = [
      ->(key) { "LocalizedStringKey\\s*\\(\\s*\"#{key}\"" },
      ->(key) { "LocalizedStringKey\\s*=\\s*\"#{key}\"" },
      ->(key) { ":\\s*LocalizedStringResource\\s*=\\s*\"#{key}\"" },
      ->(key) { "\"#{key}\"\\.localized" }
    ].freeze
    SWIFT_STRING_BODY_PATTERN = AppleStringLiteral::BODY_PATTERN
    private_constant :SWIFT_STRING_BODY_PATTERN

    IOS_STATIC_SINGLE_LINE_DISCOVERY_PATTERNS = [
      /LocalizedStringKey\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"\s*\)/,
      /:\s*LocalizedStringKey\s*=\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"/,
      /:\s*LocalizedStringResource\s*=\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"/,
      /"(?<key>#{SWIFT_STRING_BODY_PATTERN})"\.localized\b/
    ].freeze

    LOCALIZED_RESOURCE_SINGLE_LINE_DISCOVERY_PATTERNS = [
      /LocalizedStringResource\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"[^\n]*?\bdefaultValue:\s*"(?<text>#{SWIFT_STRING_BODY_PATTERN})"/,
      /LocalizedStringResource\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"/
    ].freeze

    IOS_STATIC_MULTILINE_DISCOVERY_PATTERNS = [
      /Text\s*\(\s*LocalizedStringKey\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"\s*\)[\s\S]*?\)/
    ].freeze

    LOCALIZED_RESOURCE_MULTILINE_DISCOVERY_PATTERNS = [
      /LocalizedStringResource\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"[\s\S]*?\bdefaultValue:\s*"(?<text>#{SWIFT_STRING_BODY_PATTERN})"/,
      /LocalizedStringResource\s*\(\s*"(?<key>#{SWIFT_STRING_BODY_PATTERN})"/
    ].freeze

    OPTIONAL_ARGUMENT_LABEL_PATTERN = '(?:[A-Za-z_]\w*\s*:\s*)?'
    private_constant :OPTIONAL_ARGUMENT_LABEL_PATTERN

    ANDROID_DISCOVERY_PATTERNS = {
      string: %r{R\.string\.(\w+)\b|@string/([\w.]+)\b|[(\s,=]string\.(\w+)\b}x,
      plural: %r{R\.plurals\.(\w+)\b|@plurals/([\w.]+)\b|[(\s,=]plurals\.(\w+)\b}x,
      array: %r{R\.array\.(\w+)\b|@array/([\w.]+)\b|[(\s,=]array\.(\w+)\b}x
    }.freeze

    def self.functions_with_defaults(functions)
      configured = Array(functions).map(&:strip).reject(&:empty?)
      (DEFAULT_SWIFT_FUNCTIONS + configured).uniq { |function| function.sub(/\(\s*\z/, '') }.freeze
    end

    def self.swift_string_content_pattern(value)
      encoded = value.each_char.map do |character|
        case character
        when '\\' then '\\\\'
        when '"' then '\\"'
        when "\n" then '\n'
        when "\r" then '\r'
        when "\t" then '\t'
        else character
        end
      end.join
      Regexp.escape(encoded)
    end

    def initialize(swift_functions: nil)
      @swift_functions = self.class.functions_with_defaults(swift_functions)
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
      escaped_key = self.class.swift_string_content_pattern(key)
      function_patterns = swift_function_key_patterns(escaped_key)
      function_patterns + IOS_STATIC_SEARCH_BUILDERS.map { |builder| builder.call(escaped_key) }
    end

    def ios_multiline_search_patterns(key)
      escaped_key = self.class.swift_string_content_pattern(key)
      swift_function_key_patterns(escaped_key).map { |pattern| Regexp.new(pattern) }
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
        (LOCALIZED_RESOURCE_SINGLE_LINE_DISCOVERY_PATTERNS +
          function_discovery_patterns(multiline: false) +
          IOS_STATIC_SINGLE_LINE_DISCOVERY_PATTERNS).freeze
    end

    def ios_multiline_discovery_patterns
      @ios_multiline_discovery_patterns ||=
        (LOCALIZED_RESOURCE_MULTILINE_DISCOVERY_PATTERNS +
          function_discovery_patterns(multiline: true) +
          IOS_STATIC_MULTILINE_DISCOVERY_PATTERNS).freeze
    end

    def ios_call_start_patterns
      @ios_call_start_patterns ||=
        @swift_functions.map { |function| Regexp.new(swift_function_opener(function)) }.freeze
    end

    def ios_wrapper_definition_pattern
      @ios_wrapper_definition_pattern ||= begin
        functions = (@swift_functions.map { |function| swift_call_prefix(function) } +
          ['LocalizedStringKey\\s*\\(']).join('|')
        constructor = "\\s*=\\s*(?:#{functions})"
        typed_resource = '\s*:\s*LocalizedStringResource\s*=\s*"'
        /\bstatic\s+(?:let|var)\s+(?<member_name>\w+)(?:#{constructor}|#{typed_resource})/
      end
    end

    def android_discovery_patterns
      ANDROID_DISCOVERY_PATTERNS
    end

    def swift_writer_patterns(key)
      escaped_key = self.class.swift_string_content_pattern(key)
      comment = 'comment:\\s*"(?:\\\\.|[^"\\\\])*"'

      patterns = @swift_functions.map do |function|
        Regexp.new(
          "#{swift_key_argument_prefix(function)}\"#{escaped_key}\"[^)]*#{comment}[^)]*\\)",
          Regexp::MULTILINE
        )
      end
      patterns << nested_text_writer_pattern(escaped_key, comment)
      patterns
    end

    private

    def function_discovery_patterns(multiline:)
      tail = multiline ? '[\\s\\S]*?' : '[^\\n]*?'
      @swift_functions.flat_map do |function|
        prefix = swift_key_argument_prefix(function)
        [
          Regexp.new("#{prefix}\\s*@?\"(?<key>#{SWIFT_STRING_BODY_PATTERN})\"#{tail}comment:\\s*\"(?<comment>#{SWIFT_STRING_BODY_PATTERN})\""),
          Regexp.new("#{prefix}\\s*@?\"(?<key>#{SWIFT_STRING_BODY_PATTERN})\"")
        ]
      end
    end

    def swift_function_key_patterns(escaped_key)
      @swift_functions.map do |function|
        "#{swift_key_argument_prefix(function)}@?\"#{escaped_key}\""
      end
    end

    def swift_key_argument_prefix(function)
      prefix = swift_call_prefix(function)
      return "#{prefix}\\s*" if explicit_argument_fragment?(function) || DEFAULT_SWIFT_FUNCTIONS.include?(function)

      "#{prefix}\\s*#{OPTIONAL_ARGUMENT_LABEL_PATTERN}"
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

    def explicit_argument_fragment?(function)
      _name, arguments = function.split('(', 2)
      arguments && !arguments.strip.empty?
    end

    def nested_text_writer_pattern(escaped_key, comment)
      Regexp.new(
        "Text\\s*\\(\\s*LocalizedStringKey\\s*\\(\\s*\"#{escaped_key}\"\\s*\\)" \
        "[^)]*#{comment}[^)]*\\)",
        Regexp::MULTILINE
      )
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
