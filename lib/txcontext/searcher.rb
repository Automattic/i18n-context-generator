# frozen_string_literal: true

module Txcontext
  class Searcher
    # Represents a code match with surrounding context
    Match = Data.define(:file, :line, :match_line, :context) do
      def initialize(file:, line:, match_line: "", context: "")
        super
      end
    end

    # Common locations where ripgrep might be installed
    RIPGREP_PATHS = [
      "rg",                                    # In PATH
      "/opt/homebrew/bin/rg",                  # Homebrew on Apple Silicon
      "/usr/local/bin/rg",                     # Homebrew on Intel Mac / Linux
      "/usr/bin/rg",                           # System install
    ].freeze

    # Patterns that indicate false positive matches (not actual localization usage)
    FALSE_POSITIVE_PATTERNS = [
      /\.\w+\(\s*\)/, # Method calls like .apply(), .close(), .clear()
      /==\s*["']/, # String comparisons like == "yes"
      /["']\s*==/, # String comparisons like "yes" ==
      /!=\s*["']/, # String comparisons like != "no"
      /["']\s*!=/, # String comparisons like "no" !=
      /\.equals\(["']/, # Java .equals("string")
      /contentEquals\(["']/, # Kotlin contentEquals
    ].freeze

    def initialize(source_paths:, ignore_patterns:, context_lines: 15, platform: nil)
      @source_paths = source_paths
      @ignore_patterns = ignore_patterns
      @context_lines = context_lines
      @platform = platform || detect_platform
      @rg_path = find_ripgrep!
    end

    def search(key)
      # Use platform-specific patterns for better matches
      patterns = build_search_patterns(key)

      all_matches = []
      patterns.each do |pattern|
        cmd = build_rg_command(pattern)
        output, status = Open3.capture2(cmd)

        next unless status.success? && !output.empty?

        matches = parse_rg_output(output)
        all_matches.concat(matches)
      end

      # Filter out false positives and deduplicate
      filter_matches(all_matches, key)
    end

    private

    def detect_platform
      # Detect platform based on source file extensions
      @source_paths.each do |path|
        next unless File.exist?(path)

        if File.directory?(path)
          return :ios if Dir.glob(File.join(path, "**", "*.swift")).any?
          return :android if Dir.glob(File.join(path, "**", "*.kt")).any?
        elsif path.end_with?(".swift", ".m", ".mm")
          return :ios
        elsif path.end_with?(".kt", ".java")
          return :android
        end
      end
      :unknown
    end

    def build_search_patterns(key)
      case @platform
      when :ios
        build_ios_patterns(key)
      when :android
        build_android_patterns(key)
      else
        # Fallback: search for both platform patterns plus raw key
        build_ios_patterns(key) + build_android_patterns(key) + [Regexp.escape(key)]
      end
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

    def find_ripgrep!
      # Check environment variable first
      if ENV["RIPGREP_PATH"] && File.executable?(ENV["RIPGREP_PATH"])
        return ENV["RIPGREP_PATH"]
      end

      # Try common locations
      RIPGREP_PATHS.each do |path|
        # For "rg", try to find it in PATH
        if path == "rg"
          found = `command -v rg 2>/dev/null`.strip
          return found unless found.empty?
        elsif File.executable?(path)
          return path
        end
      end

      raise Error, <<~MSG
        ripgrep (rg) is required but not found.

        Install it with:
          brew install ripgrep    # macOS
          apt install ripgrep     # Debian/Ubuntu
          cargo install ripgrep   # Rust

        Or set RIPGREP_PATH environment variable to the rg binary location.
      MSG
    end

    def build_rg_command(pattern)
      parts = [@rg_path, "--json"]

      # Add context lines
      parts += ["-C", @context_lines.to_s]

      # Add ignore patterns
      @ignore_patterns.each { |p| parts += ["-g", "!#{p}"] }

      # Search pattern (already escaped appropriately)
      parts << pattern

      # Add source paths
      parts += @source_paths

      parts.shelljoin
    end

    def parse_rg_output(output)
      matches = []
      current_file = nil
      current_line = nil
      current_match_line = nil
      context_before = []
      context_after = []
      collecting_after = false

      output.each_line do |line|
        data = Oj.load(line)
        type = data["type"]

        case type
        when "begin"
          # New file
          current_file = data.dig("data", "path", "text")
        when "match"
          # Found a match - save previous match if exists
          if current_line && current_file
            matches << build_match(current_file, current_line, current_match_line, context_before, context_after)
          end

          current_line = data.dig("data", "line_number")
          current_match_line = data.dig("data", "lines", "text")&.chomp
          context_before = []
          context_after = []
          collecting_after = true
        when "context"
          context_text = data.dig("data", "lines", "text")&.chomp
          if collecting_after && current_line
            line_num = data.dig("data", "line_number")
            if line_num && line_num > current_line
              context_after << context_text
            else
              context_before << context_text
            end
          end
        when "end"
          # End of file - save last match
          if current_line && current_file
            matches << build_match(current_file, current_line, current_match_line, context_before, context_after)
          end
          current_file = nil
          current_line = nil
          current_match_line = nil
          context_before = []
          context_after = []
          collecting_after = false
        end
      end

      matches
    end

    def build_match(file, line, match_line, context_before, context_after)
      # Build full context with the match line in the middle
      context_parts = []
      context_parts += context_before unless context_before.empty?
      context_parts << ">>> #{match_line}" if match_line
      context_parts += context_after unless context_after.empty?

      Match.new(
        file: file,
        line: line,
        match_line: match_line || "",
        context: context_parts.join("\n")
      )
    end

    def filter_matches(matches, key)
      # Deduplicate by file:line
      seen = Set.new
      filtered = []

      matches.each do |match|
        location = "#{match.file}:#{match.line}"
        next if seen.include?(location)

        # Skip if the match line looks like a false positive
        next if false_positive?(match.match_line, key)

        # Skip matches in translation files themselves (we want usage, not definition)
        next if translation_file?(match.file)

        seen.add(location)
        filtered << match
      end

      filtered
    end

    def false_positive?(line, key)
      return false if line.nil? || line.empty?

      # Check for common false positive patterns
      FALSE_POSITIVE_PATTERNS.any? { |pattern| line.match?(pattern) }
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

require "open3"
require "set"
