# frozen_string_literal: true

module Txcontext
  # File-based cache for LLM results, keyed by translation key and source context.
  class Cache
    CACHE_DIR = '.txcontext-cache'
    # Bump this when prompt format, search heuristics, or output schema change
    CACHE_VERSION = 'v2'

    def initialize(enabled: true)
      @enabled = enabled
      FileUtils.mkdir_p(CACHE_DIR) if @enabled && !File.directory?(CACHE_DIR)
    end

    def get(key, text)
      return nil unless @enabled

      path = cache_path(key, text)
      return nil unless File.exist?(path)

      Oj.load_file(path, symbol_keys: true)

      # Return the cached data as a hash (will be converted to ExtractionResult by caller)
    rescue StandardError => e
      warn "Cache read error for #{key}: #{e.message}"
      nil
    end

    def set(key, text, result)
      return unless @enabled

      path = cache_path(key, text)
      File.write(path, Oj.dump(result, indent: 2, mode: :compat))
    rescue StandardError => e
      warn "Cache write error for #{key}: #{e.message}"
    end

    def clear
      FileUtils.rm_rf(CACHE_DIR) if File.directory?(CACHE_DIR)
    end

    private

    def cache_path(key, text)
      # Include version, key, and text in hash to invalidate when any change
      hash = Digest::MD5.hexdigest("#{CACHE_VERSION}:#{key}:#{text}")
      File.join(CACHE_DIR, "#{hash}.json")
    end
  end
end
