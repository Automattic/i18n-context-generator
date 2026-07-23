# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'tempfile'

module I18nContextGenerator
  module Writers
    # Renders a writer against a temporary copy and returns a Git-style patch
    # without mutating the original file.
    class Preview
      class << self
        def render(path)
          extension = File.extname(path)
          candidate = Tempfile.new(['i18n-context-preview-', extension])
          candidate.binmode
          candidate.write(File.binread(path))
          candidate.close

          yield candidate.path
          return nil if File.binread(candidate.path) == File.binread(path)

          unified_diff(path, candidate.path)
        ensure
          candidate&.close!
        end

        private

        def unified_diff(original_path, candidate_path)
          stdout, stderr, status = Open3.capture3(
            'git', 'diff', '--no-index', '--no-prefix', '--', original_path, candidate_path
          )
          unless [0, 1].include?(status.exitstatus)
            detail = stderr.strip
            detail = 'git diff --no-index failed' if detail.empty?
            raise Error, "Unable to render preview for #{original_path}: #{detail}"
          end

          sanitize_headers(stdout, original_path)
        rescue SystemCallError => e
          raise Error, "Unable to render preview for #{original_path}: #{e.message}"
        end

        def sanitize_headers(diff, original_path)
          display_path = display_path_for(original_path)
          in_hunk = false
          diff.lines.map do |line|
            in_hunk = true if line.start_with?('@@ ')
            if !in_hunk && line.start_with?('diff --git ')
              "diff --git a/#{display_path} b/#{display_path}\n"
            elsif !in_hunk && line.start_with?('--- ')
              "--- a/#{display_path}\n"
            elsif !in_hunk && line.start_with?('+++ ')
              "+++ b/#{display_path}\n"
            else
              line
            end
          end.join
        end

        def display_path_for(original_path)
          clean_path = Pathname.new(original_path).cleanpath
          return clean_path.to_s unless clean_path.absolute?

          directory = File.dirname(clean_path.to_s)
          stdout, _stderr, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: directory)
          if status.success?
            relative = clean_path.relative_path_from(Pathname.new(stdout.strip)).cleanpath.to_s
            return relative unless relative == '..' || relative.start_with?('../')
          end

          clean_path.basename.to_s
        rescue ArgumentError, SystemCallError
          clean_path.basename.to_s
        end
      end
    end
  end
end
