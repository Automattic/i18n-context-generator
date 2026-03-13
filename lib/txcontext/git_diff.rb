# frozen_string_literal: true

require 'open3'

module Txcontext
  # Parses git diff to extract changed translation keys
  class GitDiff
    def initialize(base_ref: 'main')
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
      system('git rev-parse --git-dir > /dev/null 2>&1')
    end

    # Check if the base ref exists
    def base_ref_exists?
      system('git', 'rev-parse', '--verify', @base_ref, out: File::NULL, err: File::NULL)
    end

    private

    def git_diff_for_file(path)
      # Run git from the directory containing the file so the correct repo is used
      dir = File.directory?(path) ? path : File.dirname(path)
      # Use triple-dot to get changes on current branch since it diverged from base
      stdout, _stderr, status = Open3.capture3('git', 'diff', "#{@base_ref}...HEAD", '--', path, chdir: dir)
      status.success? ? stdout : ''
    end

    def extract_keys_from_diff(diff_output, path)
      ext = File.extname(path).downcase

      case ext
      when '.strings'
        extract_strings_keys(diff_output)
      when '.xml'
        extract_xml_keys(diff_output, path)
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
        next unless line.start_with?('+') && !line.start_with?('++')

        # Extract key from: "key" = "value";
        keys << Regexp.last_match(1) if line =~ /^\+\s*"([^"]+)"\s*=/
      end

      keys
    end

    # Extract keys from Android strings.xml diff.
    # Tracks parent element context from diff lines and uses hunk headers to
    # map added lines to file positions. When an added <item> can't be attributed
    # to a parent from diff context alone (e.g. large plural/array blocks where the
    # opener isn't in the hunk), falls back to reading the actual file.
    def extract_xml_keys(diff_output, file_path)
      keys = Set.new
      current_parent = nil
      file_line = nil
      orphaned_item_file_lines = []

      diff_output.each_line do |line|
        # Parse hunk header to track position in new file
        if (hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          file_line = hunk[1].to_i
          next
        end

        # Skip diff metadata lines
        next if line.start_with?('diff ', 'index ', '--- ', '+++ ')

        is_removed = line.start_with?('-')
        is_added = line.start_with?('+')
        content = line.sub(/^[ +-]/, '')

        # Track parent element from any visible line (context, added, or removed)
        if content =~ /<(?:plurals|string-array)\s+name=["']([^"']+)["']/
          current_parent = Regexp.last_match(1)
        elsif content =~ %r{</(?:plurals|string-array)>}
          current_parent = nil
        end

        # Process added lines for key extraction
        if is_added
          keys << Regexp.last_match(1) if content =~ /<string\s+name=["']([^"']+)["']/
          keys << Regexp.last_match(1) if content =~ /<(?:plurals|string-array)\s+name=["']([^"']+)["']/

          if content =~ /^\s*<item[\s>]/
            if current_parent
              keys << current_parent
            elsif file_line
              orphaned_item_file_lines << file_line
            end
          end
        end

        # Context and added lines exist in new file; removed lines do not
        file_line += 1 if file_line && !is_removed
      end

      # Resolve orphaned items by reading the actual file
      resolve_orphaned_items(keys, orphaned_item_file_lines, file_path)

      keys
    end

    # Build a map of file line numbers to enclosing plural/array resource names,
    # then use it to attribute orphaned <item> additions to their parent.
    def resolve_orphaned_items(keys, orphaned_lines, file_path)
      return if orphaned_lines.empty? || !File.exist?(file_path)

      current_parent = nil
      parent_at_line = {}

      File.readlines(file_path).each_with_index do |line, index|
        if line =~ /<(?:plurals|string-array)\s+name=["']([^"']+)["']/
          current_parent = Regexp.last_match(1)
        elsif line =~ %r{</(?:plurals|string-array)>}
          current_parent = nil
        end
        parent_at_line[index + 1] = current_parent
      end

      orphaned_lines.each do |line_num|
        parent = parent_at_line[line_num]
        keys << parent if parent
      end
    end
  end
end
