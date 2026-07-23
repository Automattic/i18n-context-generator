# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Cache do
  let(:cache_dir) { I18nContextGenerator::Cache::CACHE_DIR }

  after do
    FileUtils.rm_rf(cache_dir)
  end

  describe '#get and #set' do
    it 'round-trips a result' do
      cache = described_class.new(enabled: true)

      result = { key: 'test.key', text: 'Hello', description: 'A greeting' }
      cache.set('test.key', 'Hello', result)

      cached = cache.get('test.key', 'Hello')

      expect(cached[:key]).to eq('test.key')
      expect(cached[:description]).to eq('A greeting')
    end

    it 'returns nil for cache miss' do
      cache = described_class.new(enabled: true)

      expect(cache.get('nonexistent', 'text')).to be_nil
    end

    it 'differentiates by text' do
      cache = described_class.new(enabled: true)

      cache.set('key', 'text_v1', { description: 'version 1' })
      cache.set('key', 'text_v2', { description: 'version 2' })

      expect(cache.get('key', 'text_v1')[:description]).to eq('version 1')
      expect(cache.get('key', 'text_v2')[:description]).to eq('version 2')
    end

    it 'does not persist errored results' do
      cache = described_class.new(enabled: true)

      cache.set('key', 'text', { description: 'API request failed', error: 'timeout' })

      expect(cache.get('key', 'text')).to be_nil
      expect(Dir.glob(File.join(cache_dir, '*.json'))).to be_empty
    end

    it 'writes duplicate keys atomically when workers race' do
      Dir.mktmpdir do |dir|
        cache = described_class.new(enabled: true, directory: dir)
        workers = 12.times.map do |index|
          Thread.new do
            cache.set('same.key', 'Same text', { description: "Context #{index}" })
          end
        end
        workers.each(&:join)

        cached = cache.get('same.key', 'Same text')
        expect(cached[:description]).to match(/\AContext \d+\z/)
        expect(Dir.glob(File.join(dir, '*.json')).size).to eq(1)
        expect(Dir.glob(File.join(dir, '*.tmp'))).to be_empty
      end
    end

    it 'uses a configurable cache directory' do
      Dir.mktmpdir do |dir|
        custom_dir = File.join(dir, 'private-cache')
        cache = described_class.new(enabled: true, directory: custom_dir)

        cache.set('key', 'text', { description: 'Cached context' })

        expect(cache.directory).to eq(custom_dir)
        expect(Dir.glob(File.join(custom_dir, '*.json')).size).to eq(1)
      end
    end
  end

  describe 'context-based invalidation' do
    it 'returns nil when context differs' do
      cache = described_class.new(enabled: true)

      cache.set('key', 'text', { description: 'old' }, context: 'ctx_v1')

      expect(cache.get('key', 'text', context: 'ctx_v1')).not_to be_nil
      expect(cache.get('key', 'text', context: 'ctx_v2')).to be_nil
    end

    it 'invalidates when source code context changes' do
      cache = described_class.new(enabled: true)

      ctx1 = 'file.swift:10:NSLocalizedString("key"):viewDidLoad:surrounding code v1'
      ctx2 = 'file.swift:10:NSLocalizedString("key"):viewDidLoad:surrounding code v2'

      cache.set('key', 'Hello', { description: 'old context' }, context: ctx1)

      expect(cache.get('key', 'Hello', context: ctx1)[:description]).to eq('old context')
      expect(cache.get('key', 'Hello', context: ctx2)).to be_nil
    end

    it 'invalidates when model changes' do
      cache = described_class.new(enabled: true)

      ctx1 = "matches\ncomment:none\nmodel:claude-3-haiku"
      ctx2 = "matches\ncomment:none\nmodel:claude-3-sonnet"

      cache.set('key', 'text', { description: 'haiku result' }, context: ctx1)

      expect(cache.get('key', 'text', context: ctx1)).not_to be_nil
      expect(cache.get('key', 'text', context: ctx2)).to be_nil
    end
  end

  describe 'disabled cache' do
    it 'always returns nil from get' do
      cache = described_class.new(enabled: false)

      cache.set('key', 'text', { description: 'cached' })

      expect(cache.get('key', 'text')).to be_nil
    end

    it 'does not create cache directory' do
      FileUtils.rm_rf(cache_dir)

      described_class.new(enabled: false)

      expect(File.directory?(cache_dir)).to be false
    end
  end

  describe '#clear' do
    it 'removes the cache directory' do
      cache = described_class.new(enabled: true)
      cache.set('key', 'text', { description: 'data' })

      expect(File.directory?(cache_dir)).to be true

      cache.clear

      expect(File.directory?(cache_dir)).to be false
    end

    it 'does not error when cache directory does not exist' do
      cache = described_class.new(enabled: false)
      FileUtils.rm_rf(cache_dir)

      expect { cache.clear }.not_to raise_error
    end

    it 'removes legacy MD5 cache entries when clearing after an upgrade' do
      cache = described_class.new(enabled: true)
      cache.set('key', 'text', { description: 'current data' })
      File.write(File.join(cache_dir, "#{'a' * 32}.json"), '{"description":"legacy data"}')

      cache.clear

      expect(File.directory?(cache_dir)).to be false
    end

    it 'preserves unrelated files in a custom cache directory' do
      Dir.mktmpdir do |dir|
        unrelated_path = File.join(dir, 'keep.txt')
        File.write(unrelated_path, 'client data')
        cache = described_class.new(enabled: true, directory: dir)
        cache.set('key', 'text', { description: 'data' })

        cache.clear

        expect(File.read(unrelated_path)).to eq('client data')
        expect(Dir.glob(File.join(dir, '*.json'))).to be_empty
      end
    end
  end

  describe 'cache versioning' do
    it 'uses versioned cache paths' do
      cache = described_class.new(enabled: true)

      cache.set('key', 'text', { description: 'test' })

      # The cache file should exist in the cache directory
      files = Dir.glob(File.join(cache_dir, '*.json'))
      expect(files.size).to eq(1)
    end
  end

  describe 'error handling' do
    it 'returns nil on corrupted cache file' do
      cache = described_class.new(enabled: true)
      cache.set('key', 'text', { description: 'test' })

      # Corrupt the cache file
      files = Dir.glob(File.join(cache_dir, '*.json'))
      File.write(files.first, 'not valid json{{{')

      expect(cache.get('key', 'text')).to be_nil
    end
  end
end
