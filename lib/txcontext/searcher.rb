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

    def initialize(source_paths:, ignore_patterns:, context_lines: 15)
      @source_paths = source_paths
      @ignore_patterns = ignore_patterns
      @context_lines = context_lines
      @rg_path = find_ripgrep!
    end

    def search(key)
      cmd = build_rg_command(key)
      output, status = Open3.capture2(cmd)

      return [] unless status.success? && !output.empty?

      parse_rg_output(output)
    end

    private

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

    def build_rg_command(key)
      parts = [@rg_path, "--json"]

      # Add context lines
      parts += ["-C", @context_lines.to_s]

      # Add ignore patterns
      @ignore_patterns.each { |p| parts += ["-g", "!#{p}"] }

      # Escape special regex chars in key and search for it
      escaped_key = Regexp.escape(key)
      parts << escaped_key

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
  end
end

require "open3"
