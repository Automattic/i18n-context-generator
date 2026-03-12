# frozen_string_literal: true

RSpec.describe Txcontext::ContextExtractor do
  describe 'ExtractionResult' do
    it 'defines required fields' do
      result = Txcontext::ContextExtractor::ExtractionResult.new(
        key: 'test.key',
        text: 'Hello',
        description: 'A greeting'
      )

      expect(result.key).to eq('test.key')
      expect(result.text).to eq('Hello')
      expect(result.description).to eq('A greeting')
      expect(result.locations).to eq([])
      expect(result.error).to be_nil
    end

    it 'converts to hash' do
      result = Txcontext::ContextExtractor::ExtractionResult.new(
        key: 'k', text: 't', description: 'd',
        ui_element: 'button', tone: 'formal',
        max_length: 20, locations: ['file.swift:10']
      )

      h = result.to_h

      expect(h[:key]).to eq('k')
      expect(h[:ui_element]).to eq('button')
      expect(h[:locations]).to eq(['file.swift:10'])
    end
  end

  describe '#filter_entries (via private method)' do
    let(:entries) do
      [
        build_entry('settings.title', 'Settings'),
        build_entry('settings.save', 'Save'),
        build_entry('profile.name', 'Name'),
        build_entry('profile.email', 'Email'),
        build_entry('[special]', 'Special')
      ]
    end

    def build_extractor(key_filter:)
      config = Txcontext::Config.new(
        translations: [],
        key_filter: key_filter
      )
      Txcontext::ContextExtractor.new(config)
    end

    it 'filters by exact key' do
      extractor = build_extractor(key_filter: 'settings.title')
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to eq(['settings.title'])
    end

    it 'filters by wildcard pattern' do
      extractor = build_extractor(key_filter: 'settings.*')
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to contain_exactly('settings.title', 'settings.save')
    end

    it 'supports multiple comma-separated patterns' do
      extractor = build_extractor(key_filter: 'settings.title,profile.name')
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to contain_exactly('settings.title', 'profile.name')
    end

    it 'escapes regex metacharacters in key patterns' do
      extractor = build_extractor(key_filter: '[special]')
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to eq(['[special]'])
    end

    it 'does not treat unescaped brackets as character classes' do
      extractor = build_extractor(key_filter: '[special]')

      # Should NOT match 'settings.title' (which contains 's', 'p', 'e', 'c', 'i', 'a', 'l')
      result = extractor.send(:filter_entries, entries)

      expect(result.size).to eq(1)
      expect(result.first.key).to eq('[special]')
    end
  end

  describe '#android_base_key' do
    let(:extractor) do
      config = Txcontext::Config.new(translations: [])
      Txcontext::ContextExtractor.new(config)
    end

    it 'strips plural quantity suffix' do
      expect(extractor.send(:android_base_key, 'post_likes_count:one')).to eq('post_likes_count')
      expect(extractor.send(:android_base_key, 'post_likes_count:other')).to eq('post_likes_count')
    end

    it 'strips array index suffix' do
      expect(extractor.send(:android_base_key, 'days_of_week[0]')).to eq('days_of_week')
      expect(extractor.send(:android_base_key, 'days_of_week[12]')).to eq('days_of_week')
    end

    it 'returns plain keys unchanged' do
      expect(extractor.send(:android_base_key, 'simple_key')).to eq('simple_key')
    end
  end

  describe '#filter_by_range' do
    let(:entries) do
      (1..5).map { |i| build_entry("key_#{i}", "Text #{i}") }
    end

    it 'filters from start_key to end' do
      config = Txcontext::Config.new(translations: [], start_key: 'key_3')
      extractor = Txcontext::ContextExtractor.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_3 key_4 key_5])
    end

    it 'filters from beginning to end_key' do
      config = Txcontext::Config.new(translations: [], end_key: 'key_3')
      extractor = Txcontext::ContextExtractor.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_1 key_2 key_3])
    end

    it 'filters between start_key and end_key' do
      config = Txcontext::Config.new(translations: [], start_key: 'key_2', end_key: 'key_4')
      extractor = Txcontext::ContextExtractor.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_2 key_3 key_4])
    end

    it 'handles missing start_key gracefully' do
      config = Txcontext::Config.new(translations: [], start_key: 'nonexistent')
      extractor = Txcontext::ContextExtractor.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_1 key_2 key_3 key_4 key_5])
    end
  end

  describe '#truncate' do
    let(:extractor) do
      config = Txcontext::Config.new(translations: [])
      Txcontext::ContextExtractor.new(config)
    end

    it 'returns short strings unchanged' do
      expect(extractor.send(:truncate, 'hello', 10)).to eq('hello')
    end

    it 'truncates long strings with ellipsis' do
      expect(extractor.send(:truncate, 'a' * 50, 10)).to eq('a' * 7 + '...')
    end
  end

  private

  def build_entry(key, text, metadata: nil)
    Txcontext::Parsers::TranslationEntry.new(key: key, text: text, source_file: 'test.strings', metadata: metadata)
  end
end
