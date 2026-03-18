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
      described_class.new(config)
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

    it 'escapes regex metacharacters instead of treating them as character classes' do
      extractor = build_extractor(key_filter: '[special]')
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to eq(['[special]'])
      expect(result.size).to eq(1)
      expect(result.first.key).to eq('[special]')
    end
  end

  describe '#android_base_key' do
    let(:extractor) do
      config = Txcontext::Config.new(translations: [])
      described_class.new(config)
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
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_3 key_4 key_5])
    end

    it 'filters from beginning to end_key' do
      config = Txcontext::Config.new(translations: [], end_key: 'key_3')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_1 key_2 key_3])
    end

    it 'filters between start_key and end_key' do
      config = Txcontext::Config.new(translations: [], start_key: 'key_2', end_key: 'key_4')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_2 key_3 key_4])
    end

    it 'handles missing start_key gracefully' do
      config = Txcontext::Config.new(translations: [], start_key: 'nonexistent')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_1 key_2 key_3 key_4 key_5])
    end
  end

  describe '#filter_by_diff' do
    it 'includes Android child entries when the git diff reports a parent resource name' do
      config = Txcontext::Config.new(
        translations: ['res/values/strings.xml'],
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      git_diff = instance_double(Txcontext::GitDiff, changed_keys: Set['days_of_week'])
      entries = [
        build_entry('days_of_week[0]', 'Monday'),
        build_entry('settings.title', 'Settings')
      ]

      allow(Txcontext::GitDiff).to receive(:new).with(base_ref: 'origin/main').and_return(git_diff)

      result = extractor.send(:filter_by_diff, entries)

      expect(result.map(&:key)).to eq(['days_of_week[0]'])
    end

    it 'returns an empty array when git diff reports no changed keys' do
      config = Txcontext::Config.new(
        translations: ['Localizable.strings'],
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      git_diff = instance_double(Txcontext::GitDiff, changed_keys: Set.new)

      allow(Txcontext::GitDiff).to receive(:new).with(base_ref: 'origin/main').and_return(git_diff)

      expect(extractor.send(:filter_by_diff, [build_entry('settings.title', 'Settings')])).to eq([])
    end
  end

  describe '#run' do
    let(:validator) { instance_double(Txcontext::PlatformValidator, validate!: nil) }

    before do
      allow(Txcontext::PlatformValidator).to receive(:new).and_return(validator)
    end

    it 'prints a message and exits when no translation entries are found' do
      extractor = described_class.new(Txcontext::Config.new(translations: []))

      allow(extractor).to receive(:load_translations).and_return([])

      expect { extractor.run }.to output("No translation entries found.\n").to_stdout
    end

    it 'prints a dry-run preview and skips processing' do
      extractor = described_class.new(Txcontext::Config.new(translations: [], dry_run: true))
      entries = (1..21).map { |i| build_entry("key_#{i}", 'x' * 60) }

      allow(extractor).to receive(:load_translations).and_return(entries)
      expect(extractor).not_to receive(:process_entries)

      expect { extractor.run }
        .to output(/Loaded 21 translation keys.*Dry run - would process these keys:.*\.\.\. and 1 more/m)
        .to_stdout
    end
  end

  describe '#process_entry' do
    let(:config) do
      Txcontext::Config.new(
        translations: [],
        model: 'gpt-5-mini',
        max_matches_per_key: 2
      )
    end
    let(:extractor) { described_class.new(config) }
    let(:entry) do
      build_entry(
        'settings.title',
        'Settings',
        metadata: { comment: 'Shown in the settings navigation bar' }
      )
    end
    let(:match_one) do
      build_match(
        file: '/tmp/SettingsViewController.swift',
        line: 10,
        match_line: 'NSLocalizedString("settings.title", comment: "")',
        context: '>>> NSLocalizedString("settings.title", comment: "")',
        enclosing_scope: 'func viewDidLoad'
      )
    end
    let(:match_two) do
      build_match(
        file: '/tmp/SettingsHeaderView.swift',
        line: 18,
        match_line: 'Text("settings.title", comment: "")',
        context: '>>> Text("settings.title", comment: "")',
        enclosing_scope: 'struct SettingsHeaderView'
      )
    end
    let(:match_three) do
      build_match(
        file: '/tmp/SettingsFooterView.swift',
        line: 24,
        match_line: 'Text("settings.title", comment: "")',
        context: '>>> Text("settings.title", comment: "")',
        enclosing_scope: 'struct SettingsFooterView'
      )
    end

    it 'returns a placeholder result when no usage is found' do
      searcher = instance_double(Txcontext::Searcher, search: [])

      allow(extractor).to receive(:searcher).and_return(searcher)

      result = extractor.send(:process_entry, entry)

      expect(result.description).to eq('No usage found in source code')
      expect(result.locations).to eq([])
      expect(result.error).to be_nil
    end

    it 'limits matches, forwards translation comments, and caches the result' do
      searcher = instance_double(Txcontext::Searcher, search: [match_one, match_two, match_three])
      cache = instance_double(Txcontext::Cache)
      llm = instance_double(Txcontext::LLM::OpenAI)
      llm_result = Txcontext::LLM::ContextResult.new(
        description: 'Navigation title for the settings screen',
        ui_element: 'title',
        tone: 'neutral',
        max_length: 20
      )

      allow(cache).to receive(:get).and_return(nil)
      expect(llm).to receive(:generate_context).with(
        key: 'settings.title',
        text: 'Settings',
        matches: [match_one, match_two],
        model: 'gpt-5-mini',
        comment: 'Shown in the settings navigation bar',
        include_file_paths: false,
        redact_prompts: true
      ).and_return(llm_result)
      expect(cache).to receive(:set) do |key, text, result, context:|
        expect(key).to eq('settings.title')
        expect(text).to eq('Settings')
        expect(result[:description]).to eq('Navigation title for the settings screen')
        expect(context).to include('comment:Shown in the settings navigation bar')
        expect(context).to include('model:gpt-5-mini')
        expect(context).to include('include_file_paths:false')
        expect(context).to include('redact_prompts:true')
      end

      allow(extractor).to receive(:searcher).and_return(searcher)
      allow(extractor).to receive(:cache).and_return(cache)
      allow(extractor).to receive(:llm).and_return(llm)

      result = extractor.send(:process_entry, entry)

      expect(result.description).to eq('Navigation title for the settings screen')
      expect(result.locations).to eq(
        ['/tmp/SettingsViewController.swift:10', '/tmp/SettingsHeaderView.swift:18']
      )
    end

    it 'omits translation comments when the config disables them' do
      config = Txcontext::Config.new(
        translations: [],
        include_translation_comments: false
      )
      extractor = described_class.new(config)
      searcher = instance_double(Txcontext::Searcher, search: [match_one])
      cache = instance_double(Txcontext::Cache, get: nil, set: nil)
      llm = instance_double(Txcontext::LLM::OpenAI)

      expect(llm).to receive(:generate_context).with(hash_including(comment: nil)).and_return(
        Txcontext::LLM::ContextResult.new(description: 'Settings title')
      )

      allow(extractor).to receive(:searcher).and_return(searcher)
      allow(extractor).to receive(:cache).and_return(cache)
      allow(extractor).to receive(:llm).and_return(llm)

      extractor.send(:process_entry, entry)
    end

    it 'returns cached results without calling the llm again' do
      searcher = instance_double(Txcontext::Searcher, search: [match_one])
      cache = instance_double(
        Txcontext::Cache,
        get: {
          'key' => 'settings.title',
          'text' => 'Settings',
          'description' => 'Cached description',
          'locations' => ['/tmp/SettingsViewController.swift:10']
        }
      )
      llm = instance_double(Txcontext::LLM::OpenAI)

      allow(extractor).to receive(:searcher).and_return(searcher)
      allow(extractor).to receive(:cache).and_return(cache)
      allow(extractor).to receive(:llm).and_return(llm)
      expect(llm).not_to receive(:generate_context)

      result = extractor.send(:process_entry, entry)

      expect(result.description).to eq('Cached description')
      expect(result.locations).to eq(['/tmp/SettingsViewController.swift:10'])
    end
  end

  describe '#load_translations' do
    it 'warns about missing files and parses the ones that exist' do
      Dir.mktmpdir do |dir|
        existing = File.join(dir, 'Localizable.strings')
        missing = File.join(dir, 'Missing.strings')
        File.write(existing, '"settings.title" = "Settings";')

        config = Txcontext::Config.new(translations: [existing, missing])
        extractor = described_class.new(config)
        parser = instance_double(
          Txcontext::Parsers::StringsParser,
          parse: [build_entry('settings.title', 'Settings')]
        )

        allow(Txcontext::Parsers::Base).to receive(:for).with(existing).and_return(parser)

        result = nil
        expect do
          result = extractor.send(:load_translations)
        end.to output(/Translation file not found: #{Regexp.escape(missing)}/).to_stderr

        expect(result.map(&:key)).to eq(['settings.title'])
      end
    end
  end

  describe '#write_output' do
    it 'uses the JSON writer for json output' do
      config = Txcontext::Config.new(translations: [], output_path: 'out.json', output_format: 'json')
      extractor = described_class.new(config)
      writer = instance_double(Txcontext::Writers::JsonWriter, write: nil)

      allow(Txcontext::Writers::JsonWriter).to receive(:new).and_return(writer)
      extractor.results << build_result('settings.title', 'Settings title')

      extractor.send(:write_output)

      expect(writer).to have_received(:write).with(extractor.results, 'out.json')
    end

    it 'uses the CSV writer for non-json output' do
      config = Txcontext::Config.new(translations: [], output_path: 'out.csv', output_format: 'csv')
      extractor = described_class.new(config)
      writer = instance_double(Txcontext::Writers::CsvWriter, write: nil)

      allow(Txcontext::Writers::CsvWriter).to receive(:new).and_return(writer)
      extractor.results << build_result('settings.title', 'Settings title')

      extractor.send(:write_output)

      expect(writer).to have_received(:write).with(extractor.results, 'out.csv')
    end
  end

  describe '#source_writer_for' do
    let(:extractor) { described_class.new(Txcontext::Config.new(translations: [])) }

    it 'selects the strings writer for .strings files' do
      expect(extractor.send(:source_writer_for, 'ios/Localizable.strings'))
        .to be_a(Txcontext::Writers::StringsWriter)
    end

    it 'selects the Android XML writer for Android string resources' do
      expect(extractor.send(:source_writer_for, 'android/res/values/strings.xml'))
        .to be_a(Txcontext::Writers::AndroidXmlWriter)
    end

    it 'returns nil for unsupported XML files' do
      expect(extractor.send(:source_writer_for, 'android/res/layout/activity_main.xml')).to be_nil
    end
  end

  describe '#truncate' do
    let(:extractor) do
      config = Txcontext::Config.new(translations: [])
      described_class.new(config)
    end

    it 'returns short strings unchanged' do
      expect(extractor.send(:truncate, 'hello', 10)).to eq('hello')
    end

    it 'truncates long strings with ellipsis' do
      expect(extractor.send(:truncate, 'a' * 50, 10)).to eq("#{'a' * 7}...")
    end
  end

  private

  def build_entry(key, text, metadata: nil)
    Txcontext::Parsers::TranslationEntry.new(key: key, text: text, source_file: 'test.strings', metadata: metadata)
  end

  def build_match(file:, line:, match_line:, context:, enclosing_scope:)
    Txcontext::Searcher::Match.new(
      file: file,
      line: line,
      match_line: match_line,
      context: context,
      enclosing_scope: enclosing_scope
    )
  end

  def build_result(key, description)
    described_class::ExtractionResult.new(key: key, text: 'text', description: description)
  end
end
