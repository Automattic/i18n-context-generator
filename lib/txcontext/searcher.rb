# frozen_string_literal: true

require 'find'

module Txcontext
  # Finds where translation keys are used in iOS and Android source code.
  class Searcher
    # Represents a code match with surrounding context
    Match = Data.define(:file, :line, :match_line, :context, :enclosing_scope) do
      def initialize(file:, line:, match_line: '', context: '', enclosing_scope: nil)
        super
      end
    end

    # Patterns that indicate false positive matches (not actual localization usage)
    FALSE_POSITIVE_PATTERNS = [
      /==\s*["']/,             # String comparisons like == "yes"
      /["']\s*==/,             # String comparisons like "yes" ==
      /!=\s*["']/,             # String comparisons like != "no"
      /["']\s*!=/,             # String comparisons like "no" !=
      /\.equals\(["']/,        # Java .equals("string")
      /contentEquals\(["']/    # Kotlin contentEquals
    ].freeze

    # File extensions to search by platform
    FILE_EXTENSIONS = {
      ios: %w[.swift .m .mm .h].freeze,
      android: %w[.kt .java .xml].freeze,
      unknown: %w[.swift .m .mm .h .kt .java .xml].freeze
    }.freeze

    IOS_WRAPPER_DEFINITION_PATTERN =
      /\b(static\s+)?(?:let|var)\s+(\w+)\s*=\s*(?:NSLocalizedString|String\s*\(\s*localized:|LocalizedStringKey\s*\(|Text\s*\()/
    IOS_TYPE_DECLARATION_PATTERN = /\b(class|struct|enum|extension)\s+(\w+)/

    def initialize(source_paths:, ignore_patterns:, context_lines: 15, platform: nil)
      @source_paths = source_paths
      @ignore_patterns = compile_ignore_patterns(ignore_patterns)
      @context_lines = context_lines
      @platform = platform || detect_platform

      # Cache discovered files for repeated searches
      @files_cache = nil
      @file_lines_cache = {}
    end

    def search(key)
      patterns = build_search_patterns(key)
      files = discover_files
      direct_matches = []

      files.each do |file|
        matches = search_file(file, patterns, key)
        direct_matches.concat(matches)
      end

      all_matches = if @platform == :ios
                      search_ios_wrapper_usages(direct_matches, files) + direct_matches
                    else
                      direct_matches
                    end

      filter_matches(all_matches, key)
    end

    private

    def detect_platform
      @source_paths.each do |path|
        next unless File.exist?(path)

        if File.directory?(path)
          Find.find(path) do |f|
            if File.directory?(f) && ignored?(f)
              Find.prune
              next
            end

            next unless File.file?(f)
            next if ignored?(f)

            return :ios if f.end_with?('.swift', '.m', '.mm', '.h')
            return :android if f.end_with?('.kt', '.java')
          end
        elsif !ignored?(path) && path.end_with?('.swift', '.m', '.mm', '.h')
          return :ios
        elsif !ignored?(path) && path.end_with?('.kt', '.java')
          return :android
        end
      end
      :unknown
    end

    def compile_ignore_patterns(patterns)
      patterns.map { |p| glob_to_regex(p) }
    end

    def glob_to_regex(glob_pattern)
      # Convert glob pattern to regex
      # Handle common glob patterns: *, **, ?
      regex_str = Regexp.escape(glob_pattern)
                        .gsub('\*\*/', '(.*/)?')  # **/ matches any path (including empty)
                        .gsub('\*\*', '.*')       # ** matches anything
                        .gsub('\*', '[^/]*')      # * matches within path segment
                        .gsub('\?', '.')          # ? matches single char
      Regexp.new("(?:^|/)#{regex_str}(?:$|/)")
    end

    def discover_files
      return @files_cache if @files_cache

      extensions = FILE_EXTENSIONS[@platform] || FILE_EXTENSIONS[:unknown]
      files = []

      @source_paths.each do |path|
        if File.file?(path)
          files << path if extensions.any? { |ext| path.end_with?(ext) }
        elsif File.directory?(path)
          # Build a single glob pattern for all extensions
          ext_pattern = extensions.size == 1 ? "*#{extensions.first}" : "*{#{extensions.join(',')}}"
          files.concat(Dir.glob(File.join(path, '**', ext_pattern)))
        end
      end

      # Apply ignore patterns and cache
      @files_cache = files.reject { |f| ignored?(f) }
    end

    def ignored?(file)
      @ignore_patterns.any? { |pattern| pattern.match?(file) }
    end

    def search_file(file, patterns, key, enable_multiline: true)
      matches = []
      lines = []
      match_indices = Set.new

      # Read file and find all matching line indices in a single pass
      File.foreach(file).with_index do |line, index|
        line = line.chomp
        lines << line

        # Check if any pattern matches this line
        match_indices << index if patterns.any? { |pattern| pattern.match?(line) }
      end

      # For iOS files, also check for multi-line NSLocalizedString patterns
      # where the function call and key are on different lines
      if enable_multiline && @platform == :ios && file.end_with?('.swift', '.m', '.mm', '.h')
        multiline_matches = find_multiline_ios_matches(lines, patterns, key)
        match_indices.merge(multiline_matches)
      end

      # Build Match objects for each match with context
      match_indices.each do |match_index|
        context = extract_context(lines, match_index)
        scope = extract_enclosing_scope(lines, match_index)
        matches << Match.new(
          file: file,
          line: match_index + 1, # 1-indexed line numbers
          match_line: lines[match_index],
          context: context,
          enclosing_scope: scope
        )
      end

      matches
    rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR => e
      # Skip files that can't be read
      warn "Warning: Could not read #{file}: #{e.message}" if $VERBOSE
      []
    rescue ArgumentError => e
      # Skip files with encoding issues (binary files, etc.)
      return [] if e.message.include?('invalid byte sequence')

      raise
    end

    def search_ios_wrapper_usages(direct_matches, files)
      references = direct_matches.filter_map do |match|
        ios_wrapper_reference(match)
      end.uniq

      references.flat_map do |reference|
        matches = []
        local_pattern = ios_wrapper_local_pattern(reference)
        qualified_pattern = ios_wrapper_qualified_pattern(reference)

        matches.concat(
          search_file(reference[:definition_file], [local_pattern], reference[:member_name], enable_multiline: false)
        )

        cross_file_pattern = qualified_pattern || local_pattern
        cross_file_candidates = if qualified_pattern || reference[:type_path].size == 1
                                  files.reject { |file| file == reference[:definition_file] }
                                else
                                  []
                                end

        cross_file_candidates.each do |file|
          matches.concat(search_file(file, [cross_file_pattern], reference[:member_name], enable_multiline: false))
        end

        matches.reject do |match|
          match.file == reference[:definition_file] && match.line == reference[:definition_line]
        end
      end
    end

    def ios_wrapper_reference(match)
      return unless File.extname(match.file).downcase == '.swift'

      lines = cached_file_lines(match.file)
      definition_index = find_ios_wrapper_definition_index(lines, match.line - 1)
      return unless definition_index

      definition_line = lines[definition_index]
      definition_match = IOS_WRAPPER_DEFINITION_PATTERN.match(definition_line)
      return unless definition_match&.captures&.first

      type_path = find_ios_type_path(lines, definition_index)
      return if type_path.empty?

      {
        type_path: type_path,
        member_name: definition_match[2],
        definition_file: match.file,
        definition_line: definition_index + 1
      }
    end

    def cached_file_lines(file)
      @file_lines_cache[file] ||= File.readlines(file, chomp: true)
    end

    def find_ios_wrapper_definition_index(lines, match_index, lookback: 5)
      start_idx = [0, match_index - lookback].max

      match_index.downto(start_idx) do |index|
        return index if IOS_WRAPPER_DEFINITION_PATTERN.match?(lines[index])
      end

      nil
    end

    def find_ios_type_path(lines, index)
      scope_stack = []
      brace_depth = 0
      pending_type = nil

      lines[0..index].each do |line|
        if (type_match = IOS_TYPE_DECLARATION_PATTERN.match(line))
          if line.include?('{')
            scope_stack << { name: type_match[2], depth: brace_depth + 1 }
          else
            pending_type = { name: type_match[2], depth: brace_depth + 1 }
          end
        elsif pending_type && line.include?('{')
          scope_stack << pending_type
          pending_type = nil
        end

        brace_depth += line.count('{') - line.count('}')
        scope_stack.pop while scope_stack.any? && scope_stack.last[:depth] > brace_depth
      end

      scope_stack.map { |scope| scope[:name] }
    end

    def ios_wrapper_local_pattern(reference)
      local_type_name = reference[:type_path].last
      Regexp.new("\\b#{Regexp.escape(local_type_name)}\\.#{Regexp.escape(reference[:member_name])}\\b")
    end

    def ios_wrapper_qualified_pattern(reference)
      return nil unless reference[:type_path].size > 1

      qualified_type_path = reference[:type_path].join('.')
      Regexp.new("\\b#{Regexp.escape(qualified_type_path)}\\.#{Regexp.escape(reference[:member_name])}\\b")
    end

    # Find matches where localization calls span multiple lines
    # e.g., NSLocalizedString(\n    "key",\n    comment: "...")
    def find_multiline_ios_matches(lines, patterns, key)
      key_pattern = /["']#{Regexp.escape(key)}["']/

      lines.each_with_index.filter_map do |line, index|
        next if patterns.any? { |p| p.match?(line) }  # Already a single-line match
        next unless key_pattern.match?(line)          # Doesn't contain the key

        index if preceded_by_localization_opener?(lines, index)
      end.to_set
    end

    def preceded_by_localization_opener?(lines, index, lookback: 5)
      start_idx = [0, index - lookback].max

      (start_idx...index).reverse_each do |i|
        line = lines[i]
        return true if IOS_FUNCTION_OPENERS.any? { |opener| opener.match?(line) }
        return false if line =~ /;\s*$/ || line =~ /\)\s*$/ # Hit a statement boundary
      end

      false
    end

    # Scan backwards from the match to find the nearest enclosing function/class/struct
    def extract_enclosing_scope(lines, match_index)
      match_index.downto(0) do |i|
        line = lines[i]
        return "#{::Regexp.last_match(1)} #{::Regexp.last_match(2)}" if line =~ /\b(func|class|struct|enum|protocol)\s+(\w+)/
        # Android/Kotlin patterns
        return "#{::Regexp.last_match(1)} #{::Regexp.last_match(2)}" if line =~ /\b(fun|class|object)\s+(\w+)/
      end
      nil
    end

    def extract_context(lines, match_index)
      start_idx = [0, match_index - @context_lines].max
      end_idx = [lines.length - 1, match_index + @context_lines].min

      context_parts = (start_idx..end_idx).map do |i|
        i == match_index ? ">>> #{lines[i]}" : lines[i]
      end

      context_parts.join("\n")
    end

    def build_search_patterns(key)
      pattern_strings = case @platform
                        when :ios
                          build_ios_patterns(key)
                        when :android
                          build_android_patterns(key)
                        else
                          build_ios_patterns(key) + build_android_patterns(key) + [Regexp.escape(key)]
                        end

      # Pre-compile all patterns for this search
      pattern_strings.map { |p| Regexp.new(p) }
    end

    # Extract the base resource name from composite Android keys
    # e.g., "post_likes_count:one" -> "post_likes_count"
    #        "days_of_week[0]"     -> "days_of_week"
    def android_base_key(key)
      key.sub(/:[a-z]+$/, '').sub(/\[\d+\]$/, '')
    end

    # Patterns that indicate the start of a localization function call
    # Used for multi-line matching when the key is on a different line
    IOS_FUNCTION_OPENERS = [
      /NSLocalizedString\s*\(\s*$/,
      /String\s*\(\s*localized:\s*$/,
      /LocalizedStringKey\s*\(\s*$/,
      /Text\s*\(\s*$/
    ].freeze
    private_constant :IOS_FUNCTION_OPENERS

    def build_ios_patterns(key)
      escaped = Regexp.escape(key)
      [
        # NSLocalizedString("key", ...) - most common (Swift and Obj-C)
        # Note: @? handles optional @ prefix for Objective-C @"string" syntax
        "NSLocalizedString\\s*\\(\\s*@?[\"']#{escaped}[\"']",
        # String(localized: "key", ...) - modern Swift
        "String\\s*\\(\\s*localized:\\s*[\"']#{escaped}[\"']",
        # LocalizedStringKey("key") - SwiftUI
        "LocalizedStringKey\\s*\\(\\s*[\"']#{escaped}[\"']",
        # Text("key") - SwiftUI (when using localized strings)
        "Text\\s*\\(\\s*[\"']#{escaped}[\"']",
        # .localized extension pattern
        "[\"']#{escaped}[\"']\\.localized"
      ]
    end

    def build_android_patterns(key)
      base = android_base_key(key)
      escaped_base = Regexp.escape(base)

      if key =~ /:[a-z]+$/
        # Plural key (e.g., "post_likes_count:one") — search by base name in plural resources
        [
          "R\\.plurals\\.#{escaped_base}\\b",
          "@plurals/#{escaped_base}\\b",
          "getQuantityString\\s*\\(\\s*R\\.plurals\\.#{escaped_base}",
          "\\.getQuantityString\\s*\\(\\s*R\\.plurals\\.#{escaped_base}",
          "pluralStringResource\\s*\\(\\s*R\\.plurals\\.#{escaped_base}",
          "[\\(\\s,=]plurals\\.#{escaped_base}\\b"
        ]
      elsif key =~ /\[\d+\]$/
        # Array key (e.g., "days_of_week[0]") — search by base name in array resources
        [
          "R\\.array\\.#{escaped_base}\\b",
          "@array/#{escaped_base}\\b",
          "getStringArray\\s*\\(\\s*R\\.array\\.#{escaped_base}",
          "\\.getStringArray\\s*\\(\\s*R\\.array\\.#{escaped_base}",
          "resources\\.getStringArray\\s*\\(\\s*R\\.array\\.#{escaped_base}",
          "[\\(\\s,=]array\\.#{escaped_base}\\b"
        ]
      else
        # Standard string key
        escaped = Regexp.escape(key)
        [
          "R\\.string\\.#{escaped}\\b",
          "@string/#{escaped}\\b",
          "getString\\s*\\(\\s*R\\.string\\.#{escaped}",
          "\\.getString\\s*\\(\\s*R\\.string\\.#{escaped}",
          "stringResource\\s*\\(\\s*R\\.string\\.#{escaped}",
          "[\\(\\s,=]string\\.#{escaped}\\b",
          "getString\\s*\\(\\s*string\\.#{escaped}",
          "stringResource\\s*\\(\\s*string\\.#{escaped}"
        ]
      end
    end

    def filter_matches(matches, key)
      seen = Set.new
      matches.select do |match|
        location = "#{match.file}:#{match.line}"
        next false if seen.include?(location)
        next false if false_positive?(match.match_line, key)
        next false if translation_file?(match.file)

        seen.add(location)
      end
    end

    def false_positive?(line, _key)
      return false if line.nil? || line.empty?

      FALSE_POSITIVE_PATTERNS.any? { |pattern| pattern.match?(line) }
    end

    def translation_file?(file)
      basename = File.basename(file).downcase
      ext = File.extname(file).downcase

      # Skip translation files - we want code usage, not definitions
      return true if ext == '.strings'
      return true if basename == 'strings.xml'
      return true if file.include?('/res/values') && ext == '.xml'

      false
    end
  end
end
