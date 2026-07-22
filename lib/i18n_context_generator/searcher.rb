# frozen_string_literal: true

require 'concurrent'
require_relative 'path_policy'
require_relative 'file_classifier'
require_relative 'localization_syntax'
require_relative 'searcher/comment_masking'
require_relative 'searcher/match_filtering'
require_relative 'searcher/source_discovery'

module I18nContextGenerator
  # Finds where translation keys are used in iOS and Android source code.
  class Searcher
    include CommentMasking
    include MatchFiltering
    include SourceDiscovery

    # Represents a code match with surrounding context
    Match = Data.define(:file, :line, :match_line, :context, :enclosing_scope) do
      def initialize(file:, line:, match_line: '', context: '', enclosing_scope: nil)
        super
      end
    end

    # Represents a localization entry discovered directly from source code.
    DiscoveredLocalization = Data.define(
      :key, :file, :line, :text, :comment, :resource_type, :locations, :location_groups
    ) do
      def initialize(key:, file:, line:, text: nil, comment: nil, resource_type: :string, locations: nil,
                     location_groups: nil)
        locations ||= ["#{file}:#{line}"]
        location_groups ||= [locations]
        super
      end
    end

    IOS_TYPE_DECLARATION_PATTERN = /\b(class|struct|enum|extension)\s+(\w+)/

    def initialize(source_paths:, ignore_patterns:, context_lines: 15, platform: nil, swift_functions: nil)
      @source_paths = source_paths
      @path_policy = PathPolicy.new(ignore_patterns: ignore_patterns, roots: source_paths)
      @context_lines = context_lines
      @platform = platform || detect_platform
      @localization_syntax = LocalizationSyntax.new(swift_functions: swift_functions)

      # Cache discovered files for repeated searches
      @files_cache = nil
      @files_cache_mutex = Mutex.new
      @file_lines_cache = Concurrent::Map.new
      @searchable_file_lines_cache = Concurrent::Map.new
    end

    def search(key, resource_type: nil)
      patterns = build_search_patterns(key, resource_type: resource_type)
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
        @path_policy.each_file(path) do |file|
          platform = FileClassifier.source_platform(file)
          return platform if platform
        end
      end
      :unknown
    end

    def discover_files
      return @files_cache if @files_cache

      @files_cache_mutex.synchronize do
        return @files_cache if @files_cache

        @files_cache = @path_policy.files(@source_paths) do |file|
          FileClassifier.searchable_source?(file, platform: @platform)
        end
      end
    end

    def ignored?(file, directory: false)
      @path_policy.ignored?(file, directory: directory)
    end

    def search_file(file, patterns, key, enable_multiline: true)
      matches = []
      lines = cached_file_lines(file)
      searchable_lines = searchable_file_lines(file)
      match_indices = Set.new

      # Find matching line indices using the comment-masked source while
      # retaining the original lines for prompt context and output.
      searchable_lines.each_with_index do |line, index|
        # Check if any pattern matches this line
        match_indices << index if patterns.any? { |pattern| pattern.match?(line) }
      end

      # For iOS files, also check for multi-line NSLocalizedString patterns
      # where the function call and key are on different lines
      if enable_multiline && @platform == :ios && FileClassifier.searchable_platform(file) == :ios
        multiline_matches = find_multiline_ios_matches(searchable_lines, patterns, key)
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
      definition_match = @localization_syntax.ios_wrapper_definition_pattern.match(definition_line)
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
      @file_lines_cache.compute_if_absent(file) { File.readlines(file, chomp: true) }
    end

    def searchable_file_lines(file)
      @searchable_file_lines_cache.compute_if_absent(file) do
        mask_comments(cached_file_lines(file), file)
      end
    end

    def find_ios_wrapper_definition_index(lines, match_index, lookback: 5)
      start_idx = [0, match_index - lookback].max

      match_index.downto(start_idx) do |index|
        return index if @localization_syntax.ios_wrapper_definition_pattern.match?(lines[index])
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
        return true if @localization_syntax.ios_function_openers.any? { |opener| opener.match?(line) }
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

    def build_search_patterns(key, resource_type: nil)
      @localization_syntax.search_patterns(key, platform: @platform, resource_type: resource_type)
    end

    def build_ios_patterns(key)
      @localization_syntax.ios_search_patterns(key)
    end

    def build_android_patterns(key, resource_type: nil)
      @localization_syntax.android_search_patterns(key, resource_type: resource_type)
    end
  end
end
