# frozen_string_literal: true

require 'open3'
require 'pathname'
require_relative 'apple_string_literal'
require_relative 'changed_location'
require_relative 'translation_comment_index'
require_relative 'xml_scanner'
require_relative 'android_resource'
require_relative 'xcstrings_document'
require_relative 'git_diff/xml_changes'

module I18nContextGenerator
  # Parses git diff to extract changed translation keys
  class GitDiff
    include GitDiffXmlChanges

    def initialize(base_ref: 'main', head_ref: 'HEAD')
      @base_ref = base_ref
      @head_ref = head_ref
    end

    # Get keys that were added or modified since the base ref
    # @param translation_paths [Array<String>] paths to translation files
    # @return [Set<String>] set of changed keys
    def changed_keys(translation_paths)
      changed_key_locations(translation_paths).each_key.to_set(&:last)
    end

    # Get changed translation keys together with the exact changed lines that
    # produced them. Keys are scoped by translation file so duplicate keys in
    # different files remain distinct.
    # @return [Hash{Array(String, String) => Array<ChangedLocation>}]
    def changed_key_locations(translation_paths)
      translation_paths.each_with_object({}) do |path, changes|
        next unless File.exist?(path)

        diff_output = git_diff_for_path(path)
        next if diff_output.empty?

        normalized_path = Pathname.new(path).cleanpath.to_s
        base_content, head_content = revision_contents(path) if revision_contents_needed?(path, diff_output)
        head_content ||= File.binread(path)
        key_locations = case File.extname(path).downcase
                        when '.strings'
                          extract_strings_key_locations(
                            diff_output,
                            normalized_path,
                            base_content: base_content,
                            head_content: head_content
                          )
                        when '.xcstrings'
                          extract_xcstrings_key_locations(
                            diff_output,
                            normalized_path,
                            base_content: base_content,
                            head_content: head_content
                          )
                        when '.xml'
                          extract_xml_key_locations(
                            diff_output,
                            normalized_path,
                            base_content: base_content,
                            head_content: head_content
                          )
                        else
                          {}
                        end
        key_locations.each do |key, locations|
          changes[[normalized_path, key]] = locations
        end
      end
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
      in_hunk = false

      diff_output.each_line do |line|
        if line.start_with?('diff ')
          file_line = nil
          in_hunk = false
          next
        end

        if !in_hunk && (match = line.match(%r{^\+\+\+ b/(.+)$}))
          current_file = resolve_diff_file_path(path, match[1])
          next
        end

        if (hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          file_line = hunk[1].to_i
          in_hunk = true
          next
        end

        next if !in_hunk && line.start_with?('index ', '--- ', '+++ ')
        next if line.start_with?('\\')
        next if !in_hunk || file_line.nil? || current_file.nil?

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
      if Pathname.new(normalized_path).absolute?
        prefix = repository_prefix_for(path)
        relative_path = diff_file_path.delete_prefix(prefix)
        return Pathname.new(File.join(normalized_path, relative_path)).cleanpath.to_s
      end
      return Pathname.new(diff_file_path).cleanpath.to_s if normalized_path.empty? || normalized_path == '.'
      return Pathname.new(diff_file_path).cleanpath.to_s if diff_file_path == normalized_path || diff_file_path.start_with?("#{normalized_path}/")

      Pathname.new(File.join(normalized_path, diff_file_path)).cleanpath.to_s
    end

    def repository_prefix_for(path)
      @repository_prefixes ||= {}
      directory = File.directory?(path) ? path : File.dirname(path)
      @repository_prefixes[directory] ||= begin
        stdout, stderr, status = Open3.capture3('git', 'rev-parse', '--show-prefix', chdir: directory)
        if status.success?
          stdout.strip.sub(%r{/\z}, '')
        else
          detail = stderr.strip
          detail = 'unable to resolve repository path prefix' if detail.empty?
          raise Error, "Git diff failed for #{@base_ref}...#{@head_ref} (#{path}): #{detail}"
        end
      end
    end

    def merge_line_maps!(target, source)
      source.each do |file, lines|
        target[file].merge(lines)
      end
    end

    def extract_strings_key_locations(diff_output, file_path, base_content: nil, head_content: nil)
      locations = Hash.new { |hash, key| hash[key] = [] }
      head_content ||= File.binread(file_path)
      head_index = TranslationCommentIndex.new(format: :strings, content: head_content)
      base_index = TranslationCommentIndex.new(format: :strings, content: base_content) if base_content

      each_changed_diff_line(diff_output) do |content, old_line, new_line, side|
        if side == :right
          key = AppleStringLiteral.assignment_key(content) || head_index.key_at(new_line)
          locations[key] << changed_location(file_path, new_line, side: :right) if key
        elsif base_index
          key = AppleStringLiteral.assignment_key(content) || base_index.key_at(old_line)
          fallback_line = head_index.line_for_key(key)
          if key
            locations[key] << changed_location(
              file_path,
              old_line,
              side: :left,
              fallback_line: fallback_line
            )
          end
        end
      end

      prefer_right_locations(locations)
    end

    def extract_xcstrings_key_locations(diff_output, file_path, base_content: nil, head_content: nil)
      current_content = head_content || File.binread(file_path)
      head_index = xcstrings_line_index(head_content || current_content, file_path)
      base_index = xcstrings_line_index(base_content || head_content || current_content, file_path)
      locations = Hash.new { |hash, key| hash[key] = [] }
      head_lines = first_lines_by_key(head_index)

      each_changed_diff_line(diff_output) do |content, old_line, new_line, side|
        next if content.strip.empty?

        if side == :right
          key = head_index[new_line]
          locations[key] << changed_location(file_path, new_line, side: :right) if key
        else
          key = base_index[old_line]
          fallback_line = head_lines[key]
          if key
            locations[key] << changed_location(
              file_path,
              old_line,
              side: :left,
              fallback_line: fallback_line
            )
          end
        end
      end

      prefer_right_locations(locations)
    end

    def xcstrings_line_index(content, file_path)
      return {} unless content

      XcstringsDocument.new(content, path: file_path).line_index
    end

    def revision_contents_needed?(path, diff_output)
      File.extname(path).downcase == '.xcstrings' ||
        diff_output.each_line.any? { |line| line.start_with?('-') && !line.start_with?('---') }
    end

    def revision_contents(path)
      directory = File.dirname(File.expand_path(path))
      root, stderr, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: directory)
      unless status.success?
        detail = stderr.strip
        detail = 'unable to resolve repository root' if detail.empty?
        raise Error, "Git diff failed for #{@base_ref}...#{@head_ref} (#{path}): #{detail}"
      end

      repository_root = root.strip
      relative_path = Pathname.new(File.expand_path(path))
                              .relative_path_from(Pathname.new(repository_root)).to_s
      merge_base, _stderr, status = Open3.capture3(
        'git', 'merge-base', @base_ref, @head_ref, chdir: repository_root
      )
      base_revision = status.success? && !merge_base.strip.empty? ? merge_base.strip : @base_ref
      [
        file_at_revision(repository_root, relative_path, base_revision),
        file_at_revision(repository_root, relative_path, @head_ref)
      ]
    end

    def file_at_revision(repository_root, relative_path, revision)
      stdout, _stderr, status = Open3.capture3(
        'git', 'show', "#{revision}:#{relative_path}", chdir: repository_root
      )
      status.success? ? stdout : nil
    end

    def changed_location(file, line, side:, fallback_line: nil)
      ChangedLocation.new(file: file, line: line, side: side, fallback_line: fallback_line)
    end

    def prefer_right_locations(locations)
      preferred = locations.transform_values do |values|
        unique = values.uniq
        right = unique.select(&:right?)
        right.empty? ? unique : right
      end
      preferred.reject { |_key, values| values.empty? }
    end

    def first_lines_by_key(line_index)
      line_index.each_with_object({}) do |(line, key), lines|
        lines[key] ||= line
      end
    end

    def each_changed_diff_line(diff_output)
      old_line_number = nil
      new_line_number = nil
      in_hunk = false

      diff_output.each_line do |line|
        if line.start_with?('diff ')
          old_line_number = nil
          new_line_number = nil
          in_hunk = false
          next
        end

        if (match = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
          old_line_number = match[1].to_i
          new_line_number = match[2].to_i
          in_hunk = true
          next
        end
        next if !in_hunk && line.start_with?('index ', '--- ', '+++ ')
        next if line.start_with?('\\')
        next if !in_hunk || old_line_number.nil? || new_line_number.nil?

        if line.start_with?('+')
          yield(line[1..], nil, new_line_number, :right)
          new_line_number += 1
        elsif line.start_with?('-')
          yield(line[1..], old_line_number, nil, :left)
          old_line_number += 1
        else
          old_line_number += 1
          new_line_number += 1
        end
      end
    end
  end
end
