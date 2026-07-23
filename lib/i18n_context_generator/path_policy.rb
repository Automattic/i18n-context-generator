# frozen_string_literal: true

require 'find'
require 'pathname'

module I18nContextGenerator
  # Compiles client ignore globs once and applies them consistently while
  # traversing configured source roots.
  class PathPolicy
    def initialize(ignore_patterns:, roots: [])
      @ignore_patterns = self.class.compile_globs(ignore_patterns)
      @roots = roots.map { |root| normalize(root) }.uniq
    end

    def ignored?(path, directory: false)
      candidates = path_candidates(path, directory: directory)
      @ignore_patterns.any? do |pattern|
        candidates.any? { |candidate| pattern.match?(candidate) }
      end
    end

    def each_file(path)
      return enum_for(__method__, path) unless block_given?

      if File.file?(path)
        yield path unless ignored?(path)
        return
      end
      return unless File.directory?(path)
      return if ignored?(path, directory: true)

      Find.find(path) do |candidate|
        if File.directory?(candidate)
          Find.prune if candidate != path && ignored?(candidate, directory: true)
          next
        end

        yield candidate unless ignored?(candidate)
      end
    end

    def files(paths, &predicate)
      seen = {}
      paths.each_with_object([]) do |path, files|
        each_file(path) do |file|
          next if predicate && !predicate.call(file)

          identity = File.expand_path(file)
          next if seen[identity]

          seen[identity] = true
          files << file
        end
      end
    end

    class << self
      def compile_globs(patterns)
        Array(patterns).map { |pattern| glob_to_regex(pattern) }.freeze
      end

      def glob_to_regex(glob_pattern)
        regex = Regexp.escape(normalize(glob_pattern))
                      .gsub('\*\*/', '(.*/)?')
                      .gsub('\*\*', '.*')
                      .gsub('\*', '[^/]*')
                      .gsub('\?', '.')
        Regexp.new("(?:^|/)#{regex}(?:$|/)")
      end

      private

      def normalize(path)
        path.to_s.tr('\\', '/')
      end
    end

    private

    def path_candidates(path, directory:)
      normalized_path = normalize(path)
      candidates = [normalized_path]

      @roots.each do |root|
        relative = relative_to_root(normalized_path, root)
        candidates << relative if relative && !relative.empty?
      end

      return candidates.uniq unless directory

      candidates.flat_map do |candidate|
        [candidate, candidate.end_with?('/') ? candidate : "#{candidate}/"]
      end.uniq
    end

    def relative_to_root(path, root)
      return '' if path == root

      prefix = root.end_with?('/') ? root : "#{root}/"
      path.delete_prefix(prefix) if path.start_with?(prefix)
    end

    def normalize(path)
      self.class.send(:normalize, Pathname.new(path.to_s).cleanpath.to_s)
    end
  end
end
