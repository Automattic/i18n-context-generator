# frozen_string_literal: true

module Txcontext
  # Parses git diff to extract changed translation keys
  class GitDiff
    def initialize(base_ref: "main")
      @base_ref = base_ref
    end

    # Get keys that were added or modified since the base ref
    # @param translation_paths [Array<String>] paths to translation files
    # @return [Set<String>] set of changed keys
    def changed_keys(translation_paths)
      keys = Set.new

      translation_paths.each do |path|
        next unless File.exist?(path)

        diff_output = git_diff_for_file(path)
        next if diff_output.empty?

        keys.merge(extract_keys_from_diff(diff_output, path))
      end

      keys
    end

    # Check if we're in a git repository
    def self.available?
      system("git rev-parse --git-dir > /dev/null 2>&1")
    end

    # Check if the base ref exists
    def base_ref_exists?
      system("git rev-parse --verify #{@base_ref.shellescape} > /dev/null 2>&1")
    end

    private

    def git_diff_for_file(path)
      # Use triple-dot to get changes on current branch since it diverged from base
      cmd = "git diff #{@base_ref.shellescape}...HEAD -- #{path.shellescape} 2>/dev/null"
      `#{cmd}`
    end

    def extract_keys_from_diff(diff_output, path)
      ext = File.extname(path).downcase

      case ext
      when ".strings"
        extract_strings_keys(diff_output)
      when ".xml"
        extract_xml_keys(diff_output)
      else
        Set.new
      end
    end

    # Extract keys from iOS .strings diff
    # Looks for added lines like: +"key" = "value";
    def extract_strings_keys(diff_output)
      keys = Set.new

      diff_output.each_line do |line|
        # Match added or modified lines (start with +, not ++)
        next unless line.start_with?("+") && !line.start_with?("++")

        # Extract key from: "key" = "value";
        if line =~ /^\+\s*"([^"]+)"\s*=/
          keys << Regexp.last_match(1)
        end
      end

      keys
    end

    # Extract keys from Android strings.xml diff
    # Looks for added lines like: <string name="key">value</string>
    def extract_xml_keys(diff_output)
      keys = Set.new

      diff_output.each_line do |line|
        # Match added or modified lines
        next unless line.start_with?("+") && !line.start_with?("++")

        # Extract name from: <string name="key">
        if line =~ /^\+.*<string\s+name=["']([^"']+)["']/
          keys << Regexp.last_match(1)
        end

        # Also handle string-array items by parent name
        if line =~ /^\+.*<string-array\s+name=["']([^"']+)["']/
          keys << Regexp.last_match(1)
        end

        # Handle plurals
        if line =~ /^\+.*<plurals\s+name=["']([^"']+)["']/
          keys << Regexp.last_match(1)
        end
      end

      keys
    end
  end
end
