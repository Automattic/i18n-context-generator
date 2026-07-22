# frozen_string_literal: true

require 'open3'
require 'pathname'

module I18nContextGenerator
  # Parses git diff to extract changed translation keys
  class GitDiff
    def initialize(base_ref: 'main', head_ref: 'HEAD')
      @base_ref = base_ref
      @head_ref = head_ref
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

    def head_ref_exists?
      system('git', 'rev-parse', '--verify', @head_ref, out: File::NULL, err: File::NULL)
    end

    private

    def git_diff_for_path(path)
      # Run git from the directory containing the file so the correct repo is used
      dir = File.directory?(path) ? path : File.dirname(path)
      pathspec = File.directory?(path) ? '.' : File.basename(path)
      # Use triple-dot to get changes on the configured head since it diverged from base.
      stdout, stderr, status = Open3.capture3(
        'git', 'diff', "#{@base_ref}...#{@head_ref}", '--', pathspec, chdir: dir
      )
      return stdout if status.success?

      detail = stderr.strip
      detail = 'git exited unsuccessfully without an error message' if detail.empty?
      raise Error, "Git diff failed for #{@base_ref}...#{@head_ref} (#{path}): #{detail}"
    rescue SystemCallError => e
      raise Error, "Git diff failed for #{@base_ref}...#{@head_ref} (#{path}): #{e.message}"
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

      normalized_path = Pathname.new(path).cleanpath.to_s
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
      state = {
        keys: Set.new,
        current_parent: nil,
        current_string: nil,
        file_line: nil,
        orphaned_item_file_lines: [],
        pending_tag: nil
      }

      diff_output.each_line do |line|
        next if update_xml_hunk_line?(state, line)
        next if line.start_with?('diff ', 'index ', '--- ', '+++ ')

        is_removed = line.start_with?('-')
        is_added = line.start_with?('+')
        content = line.sub(/^[ +-]/, '')
        process_xml_diff_content(state, content, added: is_added) unless is_removed
        state[:file_line] += 1 if state[:file_line] && !is_removed
      end

      resolve_orphaned_items(state[:keys], state[:orphaned_item_file_lines], file_path)

      state[:keys]
    end

    def update_xml_hunk_line?(state, line)
      hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
      return false unless hunk

      state[:file_line] = hunk[1].to_i
      true
    end

    def process_xml_diff_content(state, content, added:)
      state[:keys] << state[:current_parent] if added && state[:current_parent]
      state[:keys] << state[:current_string] if added && state[:current_string]

      accumulate_xml_opening_tag(state, content, added: added)
      complete_xml_opening_tag(state) if state.dig(:pending_tag, :content)&.include?('>')
      track_xml_item_change(state) if added && content.match?(/<item\b/)

      state[:current_string] = nil if content.match?(%r{</string>})
      state[:current_parent] = nil if content.match?(%r{</(?:plurals|string-array)>})
    end

    def accumulate_xml_opening_tag(state, content, added:)
      if state[:pending_tag]
        state[:pending_tag][:content] << content
        state[:pending_tag][:added] ||= added
      elsif (tag_start = content.index(/<(?:string-array|plurals|string)\b/))
        state[:pending_tag] = { content: content[tag_start..], added: added }
      end
    end

    def complete_xml_opening_tag(state)
      tag = state[:pending_tag]
      resource = resource_from_opening_tag(tag[:content])
      if resource
        state[:keys] << resource[:name] if tag[:added]
        track_open_xml_resource(state, resource, tag[:content])
      end
      state[:pending_tag] = nil
    end

    def track_open_xml_resource(state, resource, content)
      if resource[:type] == 'string'
        state[:current_string] = resource[:name] unless content.include?('</string>')
      elsif !content.include?("</#{resource[:type]}>")
        state[:current_parent] = resource[:name]
      end
    end

    def track_xml_item_change(state)
      if state[:current_parent]
        state[:keys] << state[:current_parent]
      elsif state[:file_line]
        state[:orphaned_item_file_lines] << state[:file_line]
      end
    end

    def resource_from_opening_tag(tag)
      type_match = tag.match(/<(string-array|plurals|string)\b/)
      name_match = tag.match(/\bname\s*=\s*(["'])(.*?)\1/m)
      return unless type_match && name_match

      { type: type_match[1], name: name_match[2] }
    end

    # Build a map of file line numbers to enclosing plural/array resource names,
    # then use it to attribute orphaned <item> additions to their parent.
    def resolve_orphaned_items(keys, orphaned_lines, file_path)
      return if orphaned_lines.empty? || !File.exist?(file_path)

      current_parent = nil
      parent_at_line = {}
      pending_tag = nil

      File.readlines(file_path).each_with_index do |line, index|
        if pending_tag
          pending_tag << line
        elsif (tag_start = line.index(/<(?:plurals|string-array)\b/))
          pending_tag = line[tag_start..]
        end

        if pending_tag&.include?('>')
          resource = resource_from_opening_tag(pending_tag)
          current_parent = resource[:name] if resource
          pending_tag = nil
        end

        current_parent = nil if line.match?(%r{</(?:plurals|string-array)>})
        parent_at_line[index + 1] = current_parent
      end

      orphaned_lines.each do |line_num|
        parent = parent_at_line[line_num]
        keys << parent if parent
      end
    end
  end
end
