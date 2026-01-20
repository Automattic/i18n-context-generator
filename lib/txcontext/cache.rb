# frozen_string_literal: true

module Txcontext
  class Cache
    CACHE_DIR = ".txcontext-cache"

    def initialize(enabled: true)
      @enabled = enabled
      FileUtils.mkdir_p(CACHE_DIR) if @enabled && !File.directory?(CACHE_DIR)
    end

    def get(key, text)
      return nil unless @enabled

      path = cache_path(key, text)
      return nil unless File.exist?(path)

      data = Oj.load_file(path, symbol_keys: true)

      # Return the cached data as a hash (will be converted to ExtractionResult by caller)
      data
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
      # Include both key and text in hash to invalidate when text changes
      hash = Digest::MD5.hexdigest("#{key}:#{text}")
      File.join(CACHE_DIR, "#{hash}.json")
    end
  end
end
