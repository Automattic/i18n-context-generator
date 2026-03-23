# frozen_string_literal: true

require 'open3'
require 'pathname'

module I18nContextGenerator
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

        diff_output = git_diff_for_path(path)
        next if diff_output.empty?

        keys.merge(extract_keys_from_diff(diff_output, path))
      end

      keys
    end

    # Get changed line numbers in source files since the base ref.
    # @param source_paths [Array<String>] paths to source files or directories
    # @return [Hash{String => Set<Integer>}] changed line numbers keyed by file path
    def changed_lines(source_paths)
      source_paths.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |path, line_map|
        next unless File.exist?(path)

        diff_output = git_diff_for_path(path)
        next if diff_output.empty?

        merge_line_maps!(line_map, extract_changed_lines(diff_output, path))
      end
    end

    # Check if we're in a git repository
    def self.available?
      system('git', 'rev-parse', '--git-dir', out: File::NULL, err: File::NULL)
    end

    # Check if the base ref exists
    def base_ref_exists?
      system('git', 'rev-parse', '--verify', @base_ref, out: File::NULL, err: File::NULL)
    end

    private

    def git_diff_for_path(path)
      # Run git from the directory containing the file so the correct repo is used
      dir = File.directory?(path) ? path : File.dirname(path)
      pathspec = File.directory?(path) ? '.' : File.basename(path)
      # Use triple-dot to get changes on current branch since it diverged from base
      stdout, _stderr, status = Open3.capture3('git', 'diff', "#{@base_ref}...HEAD", '--', pathspec, chdir: dir)
      status.success? ? stdout : ''
    end

    def extract_changed_lines(diff_output, path)
      changed_lines = Hash.new { |h, k| h[k] = Set.new }
      current_file = File.file?(path) ? path : nil
      file_line = nil

      diff_output.each_line do |line|
        if (match = line.match(%r{^\+\+\+ b/(.+)$}))
          current_file = resolve_diff_file_path(path, match[1])
          next
        end

        if (hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          file_line = hunk[1].to_i
          next
        end

        next if line.start_with?('diff ', 'index ', '--- ', '+++ ', '\\')
        next if file_line.nil? || current_file.nil?

        if line.start_with?('+')
          changed_lines[current_file] << file_line
          file_line += 1
        elsif line.start_with?('-')
          next
        else
          file_line += 1
        end
      end

      changed_lines
    end

    def resolve_diff_file_path(path, diff_file_path)
      return Pathname.new(path).cleanpath.to_s if File.file?(path)

      normalized_path = path.to_s.sub(%r{/\z}, '')
      return Pathname.new(diff_file_path).cleanpath.to_s if normalized_path.empty? || normalized_path == '.'
      return Pathname.new(diff_file_path).cleanpath.to_s if diff_file_path == normalized_path || diff_file_path.start_with?("#{normalized_path}/")

      Pathname.new(File.join(normalized_path, diff_file_path)).cleanpath.to_s
    end

    def merge_line_maps!(target, source)
      source.each do |file, lines|
        target[file].merge(lines)
      end
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
