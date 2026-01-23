# frozen_string_literal: true

require "set"

module Txcontext
  class Searcher
    # Represents a code match with surrounding context
    Match = Data.define(:file, :line, :match_line, :context) do
      def initialize(file:, line:, match_line: "", context: "")
        super
      end
    end

    # Patterns that indicate false positive matches (not actual localization usage)
    FALSE_POSITIVE_PATTERNS = [
      /\.\w+\(\s*\)/,          # Method calls like .apply(), .close(), .clear()
      /==\s*["']/,             # String comparisons like == "yes"
      /["']\s*==/,             # String comparisons like "yes" ==
      /!=\s*["']/,             # String comparisons like != "no"
      /["']\s*!=/,             # String comparisons like "no" !=
      /\.equals\(["']/,        # Java .equals("string")
      /contentEquals\(["']/,   # Kotlin contentEquals
    ].freeze

    # File extensions to search by platform
    FILE_EXTENSIONS = {
      ios: %w[.swift .m .mm .h].freeze,
      android: %w[.kt .java .xml].freeze,
      unknown: %w[.swift .m .mm .h .kt .java .xml].freeze,
    }.freeze

    def initialize(source_paths:, ignore_patterns:, context_lines: 15, platform: nil)
      @source_paths = source_paths
      @ignore_patterns = compile_ignore_patterns(ignore_patterns)
      @context_lines = context_lines
      @platform = platform || detect_platform

      # Cache discovered files for repeated searches
      @files_cache = nil
    end

    def search(key)
      patterns = build_search_patterns(key)
      files = discover_files
      all_matches = []

      files.each do |file|
        matches = search_file(file, patterns)
        all_matches.concat(matches)
      end

      filter_matches(all_matches, key)
    end

    private

    def detect_platform
      @source_paths.each do |path|
        next unless File.exist?(path)

        if File.directory?(path)
          # Quick check using Find to avoid globbing entire trees
          return :ios if Dir.glob(File.join(path, "**", "*.swift"), File::FNM_DOTMATCH).first
          return :android if Dir.glob(File.join(path, "**", "*.kt"), File::FNM_DOTMATCH).first
        elsif path.end_with?(".swift", ".m", ".mm")
          return :ios
        elsif path.end_with?(".kt", ".java")
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
                        .gsub('\*\*/', ".*/")     # **/ matches any path
                        .gsub('\*\*', ".*")       # ** matches anything
                        .gsub('\*', "[^/]*")      # * matches within path segment
                        .gsub('\?', ".")          # ? matches single char
      Regexp.new(regex_str)
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
          ext_pattern = extensions.size == 1 ? "*#{extensions.first}" : "*{#{extensions.join(",")}}"
          files.concat(Dir.glob(File.join(path, "**", ext_pattern)))
        end
      end

      # Apply ignore patterns and cache
      @files_cache = files.reject { |f| ignored?(f) }
    end

    def ignored?(file)
      @ignore_patterns.any? { |pattern| pattern.match?(file) }
    end

    def search_file(file, patterns)
      matches = []
      lines = []
      match_indices = []

      # Read file and find all matching line indices in a single pass
      File.foreach(file).with_index do |line, index|
        line = line.chomp
        lines << line

        # Check if any pattern matches this line
        if patterns.any? { |pattern| pattern.match?(line) }
          match_indices << index
        end
      end

      # Build Match objects for each match with context
      match_indices.each do |match_index|
        context = extract_context(lines, match_index)
        matches << Match.new(
          file: file,
          line: match_index + 1, # 1-indexed line numbers
          match_line: lines[match_index],
          context: context
        )
      end

      matches
    rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR => e
      # Skip files that can't be read
      warn "Warning: Could not read #{file}: #{e.message}" if $VERBOSE
      []
    rescue ArgumentError => e
      # Skip files with encoding issues (binary files, etc.)
      return [] if e.message.include?("invalid byte sequence")

      raise
    end

    def extract_context(lines, match_index)
      start_idx = [0, match_index - @context_lines].max
      end_idx = [lines.length - 1, match_index + @context_lines].min

      context_parts = []

      (start_idx..end_idx).each do |i|
        if i == match_index
          context_parts << ">>> #{lines[i]}"
        else
          context_parts << lines[i]
        end
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

    def build_ios_patterns(key)
      escaped = Regexp.escape(key)
      [
        # NSLocalizedString("key", ...) - most common
        "NSLocalizedString\\s*\\(\\s*[\"']#{escaped}[\"']",
        # String(localized: "key", ...) - modern Swift
        "String\\s*\\(\\s*localized:\\s*[\"']#{escaped}[\"']",
        # LocalizedStringKey("key") - SwiftUI
        "LocalizedStringKey\\s*\\(\\s*[\"']#{escaped}[\"']",
        # Text("key") - SwiftUI (when using localized strings)
        "Text\\s*\\(\\s*[\"']#{escaped}[\"']",
        # .localized extension pattern
        "[\"']#{escaped}[\"']\\.localized",
      ]
    end

    def build_android_patterns(key)
      # Android keys use underscores, not dots typically
      escaped = Regexp.escape(key)
      [
        # R.string.key_name
        "R\\.string\\.#{escaped}\\b",
        # @string/key_name in XML
        "@string/#{escaped}\\b",
        # getString(R.string.key_name)
        "getString\\s*\\(\\s*R\\.string\\.#{escaped}",
        # context.getString(R.string.key_name)
        "\\.getString\\s*\\(\\s*R\\.string\\.#{escaped}",
        # stringResource(R.string.key_name) - Jetpack Compose
        "stringResource\\s*\\(\\s*R\\.string\\.#{escaped}",
      ]
    end

    def filter_matches(matches, key)
      seen = Set.new
      filtered = []

      matches.each do |match|
        location = "#{match.file}:#{match.line}"
        next if seen.include?(location)
        next if false_positive?(match.match_line, key)
        next if translation_file?(match.file)

        seen.add(location)
        filtered << match
      end

      filtered
    end

    def false_positive?(line, _key)
      return false if line.nil? || line.empty?

      FALSE_POSITIVE_PATTERNS.any? { |pattern| pattern.match?(line) }
    end

    def translation_file?(file)
      basename = File.basename(file).downcase
      ext = File.extname(file).downcase

      # Skip translation files - we want code usage, not definitions
      return true if ext == ".strings"
      return true if basename == "strings.xml"
      return true if file.include?("/res/values") && ext == ".xml"

      false
    end
  end
end
