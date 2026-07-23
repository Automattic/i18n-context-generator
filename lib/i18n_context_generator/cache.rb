# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'oj'
require 'tempfile'

module I18nContextGenerator
  # File-based cache for LLM results, keyed by translation key and source context.
  class Cache
    DEFAULT_DIR = '.i18n-context-generator-cache'
    CACHE_DIR = DEFAULT_DIR # Backward-compatible constant name.
    # Bump this when prompt format, search heuristics, or output schema change
    CACHE_VERSION = 'v5'

    attr_reader :directory

    def initialize(enabled: true, directory: DEFAULT_DIR)
      @enabled = enabled
      @directory = directory
      FileUtils.mkdir_p(@directory) if @enabled && !File.directory?(@directory)
    end

    def get(key, text, context: nil)
      return nil unless @enabled

      path = cache_path(key, text, context)
      return nil unless File.exist?(path)

      Oj.load_file(path, symbol_keys: true)
    rescue StandardError => e
      warn "Cache read error for #{key}: #{e.message}"
      nil
    end

    def set(key, text, result, context: nil)
      return unless @enabled
      return if result[:error] || result['error']

      path = cache_path(key, text, context)
      write_atomically(path, Oj.dump(result, indent: 2, mode: :compat))
    rescue StandardError => e
      warn "Cache write error for #{key}: #{e.message}"
    end

    def clear
      return unless File.directory?(@directory)

      Dir.children(@directory).grep(/\A(?:[a-f0-9]{32}(?:[a-f0-9]{32})?\.json|context-cache-.*\.tmp)\z/).each do |filename|
        FileUtils.rm_f(File.join(@directory, filename))
      end
      Dir.rmdir(@directory) if safe_to_remove_empty_directory? && Dir.empty?(@directory)
    end

    private

    def cache_path(key, text, context)
      # Include version, key, text, and context (match locations/code) in hash
      # so cache invalidates when source code usage changes
      hash = Digest::SHA256.hexdigest("#{CACHE_VERSION}:#{key}:#{text}:#{context}")
      File.join(@directory, "#{hash}.json")
    end

    def write_atomically(path, contents)
      tempfile = Tempfile.new(['context-cache-', '.tmp'], @directory)
      tempfile.chmod(0o600)
      tempfile.write(contents)
      tempfile.flush
      tempfile.fsync
      tempfile.close
      File.rename(tempfile.path, path)
    ensure
      tempfile&.close!
    end

    def safe_to_remove_empty_directory?
      expanded = File.expand_path(@directory)
      ![File.expand_path(File::SEPARATOR), Dir.home, Dir.pwd].include?(expanded)
    end
  end
end
