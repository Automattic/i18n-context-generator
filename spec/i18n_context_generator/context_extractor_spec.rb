# frozen_string_literal: true

RSpec.describe I18nContextGenerator::ContextExtractor do
  describe 'ExtractionResult' do
    it 'defines required fields' do
      result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'test.key',
        text: 'Hello',
        description: 'A greeting'
      )

      expect(result.key).to eq('test.key')
      expect(result.text).to eq('Hello')
      expect(result.description).to eq('A greeting')
      expect(result.locations).to eq([])
      expect(result.changed_locations).to eq([])
      expect(result.changed_location_groups).to eq([])
      expect(result.translation_key).to eq('test.key')
      expect(result.changed_translation_locations).to eq([])
      expect(result.status).to eq(:success)
      expect(result).to be_actionable
      expect(result.error).to be_nil
    end

    it 'converts to hash' do
      result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'k', text: 't', description: 'd',
        ui_element: 'button', tone: 'formal',
        max_length: 20, locations: ['file.swift:10'], changed_locations: ['file.swift:10'],
        changed_location_groups: [['file.swift:10']],
        changed_translation_locations: ['Localizable.strings:4']
      )

      h = result.to_h

      expect(h[:key]).to eq('k')
      expect(h[:ui_element]).to eq('button')
      expect(h[:locations]).to eq(['file.swift:10'])
      expect(h[:changed_locations]).to eq(['file.swift:10'])
      expect(h[:changed_location_groups]).to eq([['file.swift:10']])
      expect(h[:translation_key]).to eq('k')
      expect(h[:changed_translation_locations]).to eq(['Localizable.strings:4'])
      expect(h[:status]).to eq(:success)
    end

    it 'exposes non-actionable result states without relying on description text' do
      no_usage = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'unused', text: 'Unused', description: 'Nothing referenced this key', status: :no_usage
      )
      failed = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'failed', text: 'Failed', description: 'Provider unavailable', error: 'timeout'
      )
      blank = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'blank', text: 'Blank', description: ' '
      )

      expect([no_usage.actionable?, failed.actionable?, blank.actionable?]).to eq([false, false, false])
    end
  end

  describe '#filter_entries (via private method)' do
    let(:entries) do
      [
        build_entry('settings.title', 'Settings'),
        build_entry('settings.save', 'Save'),
        build_entry('profile.name', 'Name'),
        build_entry('profile.email', 'Email'),
        build_entry('greeting,formal', 'Formal greeting'),
        build_entry('[special]', 'Special')
      ]
    end

    def build_extractor(key_filter:)
      config = I18nContextGenerator::Config.new(
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

    it 'preserves commas inside repeatable key patterns' do
      extractor = build_extractor(key_filter: ['greeting,formal'])
      result = extractor.send(:filter_entries, entries)

      expect(result.map(&:key)).to eq(['greeting,formal'])
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
      config = I18nContextGenerator::Config.new(translations: [])
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
      config = I18nContextGenerator::Config.new(translations: [], start_key: 'key_3')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_3 key_4 key_5])
    end

    it 'filters from beginning to end_key' do
      config = I18nContextGenerator::Config.new(translations: [], end_key: 'key_3')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_1 key_2 key_3])
    end

    it 'filters between start_key and end_key' do
      config = I18nContextGenerator::Config.new(translations: [], start_key: 'key_2', end_key: 'key_4')
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, entries)

      expect(result.map(&:key)).to eq(%w[key_2 key_3 key_4])
    end

    it 'rejects missing range boundaries' do
      config = I18nContextGenerator::Config.new(translations: [], start_key: 'nonexistent')
      extractor = described_class.new(config)

      expect { extractor.send(:filter_by_range, entries) }
        .to raise_error(I18nContextGenerator::Error, /start_key not found: nonexistent/)

      end_config = I18nContextGenerator::Config.new(translations: [], end_key: 'nonexistent')
      end_extractor = described_class.new(end_config)

      expect { end_extractor.send(:filter_by_range, entries) }
        .to raise_error(I18nContextGenerator::Error, /end_key not found: nonexistent/)
    end

    it 'rejects reversed boundaries' do
      config = I18nContextGenerator::Config.new(translations: [], start_key: 'key_4', end_key: 'key_2')
      extractor = described_class.new(config)

      expect { extractor.send(:filter_by_range, entries) }
        .to raise_error(I18nContextGenerator::Error, /start_key must not come after end_key/)
    end

    it 'includes all source-scoped duplicates at a range boundary' do
      duplicate_entries = [
        build_entry('before', 'Before'),
        build_entry('shared', 'English', source_file: 'english.strings'),
        build_entry('middle', 'Middle'),
        build_entry('shared', 'French', source_file: 'french.strings'),
        build_entry('after', 'After')
      ]
      config = I18nContextGenerator::Config.new(
        translations: [],
        start_key: 'shared',
        end_key: 'shared'
      )
      extractor = described_class.new(config)

      result = extractor.send(:filter_by_range, duplicate_entries)

      expect(result.map(&:text)).to eq(%w[English Middle French])
    end
  end

  describe '#filter_by_diff' do
    it 'includes Android child entries when the git diff reports a parent resource name' do
      config = I18nContextGenerator::Config.new(
        translations: ['res/values/strings.xml'],
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      git_diff = instance_double(
        I18nContextGenerator::GitDiff,
        changed_key_locations: {
          ['res/values/strings.xml', 'days_of_week'] => ['res/values/strings.xml:4']
        }
      )
      entries = [
        build_entry('days_of_week[0]', 'Monday', source_file: 'res/values/strings.xml'),
        build_entry('settings.title', 'Settings', source_file: 'res/values/strings.xml')
      ]

      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)

      result = extractor.send(:filter_by_diff, entries)

      expect(result.map(&:key)).to eq(['days_of_week[0]'])
      expect(extractor.send(:changed_translation_locations_for, result.first))
        .to eq(['res/values/strings.xml:4'])
    end

    it 'narrows Android plural changes without rescanning the changed location' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(
          path,
          <<~XML
            <resources>
              <plurals name="item_count">
                <item quantity="one">%d item</item>
                <item quantity="other">%d total items</item>
              </plurals>
            </resources>
          XML
        )
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'item_count'] => ["#{path}:4"] }
        )
        entries = [
          build_entry('item_count:one', '%d item', source_file: path, metadata: { plural: 'item_count' }),
          build_entry('item_count:other', '%d total items', source_file: path, metadata: { plural: 'item_count' })
        ]

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)
        allow(extractor).to receive(:scan_android_collection_members).and_call_original

        result = extractor.send(:filter_by_diff, entries)
        changed_locations = extractor.send(:changed_translation_locations_for, result.first)

        expect([result.map(&:key), changed_locations]).to eq([['item_count:other'], ["#{path}:4"]])
        expect(extractor).to have_received(:scan_android_collection_members).once
      end
    end

    it 'prefers an exact Android child over an ambiguous parent location' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
            <plurals name="item_count">
              <item quantity="one">%d item</item>
              <item quantity="other">%d items</item>
            </plurals>
          </resources>
        XML
        entries = I18nContextGenerator::Parsers::AndroidXmlParser.new.parse(path)
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'item_count'] => ["#{path}:2", "#{path}:3"] }
        )

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)

        result = extractor.send(:filter_by_diff, entries)

        expect(result.map(&:key)).to eq(['item_count:one'])
        expect(extractor.send(:changed_translation_locations_for, result.first)).to eq(["#{path}:3"])
      end
    end

    it 'indexes each Android translation file once while narrowing collection locations' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
            <plurals name="item_count">

              <item quantity="one">%d item</item>
              <item quantity="other">%d items</item>
            </plurals>
          </resources>
        XML
        entries = [
          build_entry('item_count:one', '%d item', source_file: path, metadata: { plural: 'item_count' }),
          build_entry('item_count:other', '%d items', source_file: path, metadata: { plural: 'item_count' })
        ]
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'item_count'] => ["#{path}:2", "#{path}:3"] }
        )

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)
        allow(I18nContextGenerator::AndroidResource).to receive(:index).and_call_original

        extractor.send(:filter_by_diff, entries)

        expect(I18nContextGenerator::AndroidResource).to have_received(:index).once
      end
    end

    it 'narrows multiline Android array changes to the exact changed index' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(
          path,
          <<~XML
            <resources>
              <string-array
                name="weekdays">
                <item>Monday</item>
                <item>
                  Tuesday
                </item>
              </string-array>
            </resources>
          XML
        )
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'weekdays'] => ["#{path}:6"] }
        )
        entries = [
          build_entry('weekdays[0]', 'Monday', source_file: path, metadata: { array: 'weekdays', index: 0 }),
          build_entry('weekdays[1]', 'Tuesday', source_file: path, metadata: { array: 'weekdays', index: 1 })
        ]

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)

        result = extractor.send(:filter_by_diff, entries)

        expect(result.map(&:key)).to eq(['weekdays[1]'])
        expect(extractor.send(:changed_translation_locations_for, result.first)).to eq(["#{path}:6"])
      end
    end

    it 'ignores commented-out Android items when resolving an array index' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(
          path,
          <<~XML
            <resources>
              <string-array name="weekdays">
                <!-- <item>Ignored example</item> -->
                <item>Monday</item>
              </string-array>
            </resources>
          XML
        )
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'weekdays'] => ["#{path}:4"] }
        )
        entries = [
          build_entry('weekdays[0]', 'Monday', source_file: path, metadata: { array: 'weekdays', index: 0 }),
          build_entry('weekdays[1]', 'Tuesday', source_file: path, metadata: { array: 'weekdays', index: 1 })
        ]

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)

        expect(extractor.send(:filter_by_diff, entries).map(&:key)).to eq(['weekdays[0]'])
      end
    end

    it 'keeps all Android children when a changed line contains multiple items' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(
          path,
          <<~XML
            <resources>
              <string-array name="weekdays">
                <item>Monday</item><item>Tuesday</item>
              </string-array>
            </resources>
          XML
        )
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'weekdays'] => ["#{path}:3"] }
        )
        entries = [
          build_entry('weekdays[0]', 'Monday', source_file: path, metadata: { array: 'weekdays', index: 0 }),
          build_entry('weekdays[1]', 'Tuesday', source_file: path, metadata: { array: 'weekdays', index: 1 })
        ]

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)

        expect(extractor.send(:filter_by_diff, entries).map(&:key)).to eq(%w[weekdays[0] weekdays[1]])
      end
    end

    it 'resolves a later Android array child after a line containing multiple items' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(
          path,
          <<~XML
            <resources>
              <string-array name="weekdays">
                <item>Monday</item><item>Tuesday</item>
                <item>Wednesday</item>
              </string-array>
            </resources>
          XML
        )
        config = I18nContextGenerator::Config.new(translations: [path], diff_base: 'main')
        extractor = described_class.new(config)
        git_diff = instance_double(
          I18nContextGenerator::GitDiff,
          changed_key_locations: { [path, 'weekdays'] => ["#{path}:4"] }
        )
        entries = [
          build_entry('weekdays[0]', 'Monday', source_file: path, metadata: { array: 'weekdays', index: 0 }),
          build_entry('weekdays[1]', 'Tuesday', source_file: path, metadata: { array: 'weekdays', index: 1 }),
          build_entry('weekdays[2]', 'Wednesday', source_file: path, metadata: { array: 'weekdays', index: 2 })
        ]

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'main', head_ref: 'HEAD').and_return(git_diff)

        expect(extractor.send(:filter_by_diff, entries).map(&:key)).to eq(['weekdays[2]'])
      end
    end

    it 'returns an empty array when git diff reports no changed keys' do
      config = I18nContextGenerator::Config.new(
        translations: ['Localizable.strings'],
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      git_diff = instance_double(I18nContextGenerator::GitDiff, changed_key_locations: {})

      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)

      expect(extractor.send(:filter_by_diff, [build_entry('settings.title', 'Settings')])).to eq([])
    end

    it 'scopes changed duplicate keys to their translation file' do
      config = I18nContextGenerator::Config.new(
        translations: %w[english.strings french.strings],
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      git_diff = instance_double(
        I18nContextGenerator::GitDiff,
        changed_key_locations: {
          ['english.strings', 'shared.key'] => ['english.strings:1']
        }
      )
      entries = [
        build_entry('shared.key', 'English', source_file: 'english.strings'),
        build_entry('shared.key', 'French', source_file: 'french.strings')
      ]

      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)

      result = extractor.send(:filter_by_diff, entries)

      expect(result.map(&:text)).to eq(['English'])
    end
  end

  describe '#run' do
    let(:validator) { instance_double(I18nContextGenerator::PlatformValidator, validate!: nil) }

    before do
      allow(I18nContextGenerator::PlatformValidator).to receive(:new).and_return(validator)
    end

    it 'validates programmatic configuration without requiring a CLI destination' do
      config = I18nContextGenerator::Config.new(translations: [], concurrency: 0)
      extractor = described_class.new(config)

      expect { extractor.run }.to raise_error(I18nContextGenerator::Error, /concurrency/)
      expect(I18nContextGenerator::PlatformValidator).not_to have_received(:new)
    end

    it 'prints a message and exits when no source entries are found in source-first auto mode' do
      extractor = described_class.new(I18nContextGenerator::Config.new(translations: []))

      allow(extractor).to receive(:load_source_entries).and_return([])

      expect { extractor.run }.to output("No source localization entries found.\n").to_stdout
    end

    it 'prints a dry-run preview and skips processing' do
      extractor = described_class.new(I18nContextGenerator::Config.new(translations: [], dry_run: true))
      entries = (1..21).map { |i| build_entry("key_#{i}", 'x' * 60) }

      allow(extractor).to receive(:load_source_entries).and_return(entries)
      allow(extractor).to receive(:process_entries)

      expect { extractor.run }
        .to output(/Loaded 21 source localization entries.*Dry run - would process these keys:.*\.\.\. and 1 more/m)
        .to_stdout

      expect(extractor).not_to have_received(:process_entries)
    end

    it 'reports a provider configuration error once before starting workers' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: [ios_fixtures_path],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      entries = [
        build_entry('settings.title', 'Settings'),
        build_entry('settings.save', 'Save')
      ]
      allow(extractor).to receive(:load_entries).and_return(entries)
      allow(extractor).to receive(:process_entries)
      allow(I18nContextGenerator::LLM::Client).to receive(:for)
        .and_raise(I18nContextGenerator::Error, 'ANTHROPIC_API_KEY environment variable is required')

      expect { extractor.run }
        .to raise_error(
          I18nContextGenerator::Error,
          'ANTHROPIC_API_KEY environment variable is required'
        )

      expect(I18nContextGenerator::LLM::Client).to have_received(:for).once
      expect(extractor).not_to have_received(:process_entries)
      expect(extractor.errors).to be_empty
      expect(extractor.results).to be_empty
    end

    it 'passes the once-resolved platform into source discovery' do
      Dir.mktmpdir do |source_dir|
        config = I18nContextGenerator::Config.new(
          translations: [],
          source_paths: [source_dir],
          discovery_mode: 'source',
          dry_run: true
        )
        extractor = described_class.new(config)
        searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: [])
        allow(validator).to receive(:validate!).and_return(:ios)
        allow(I18nContextGenerator::Searcher).to receive(:new).and_return(searcher)

        extractor.run

        expect(I18nContextGenerator::Searcher).to have_received(:new).with(
          source_paths: [source_dir],
          ignore_patterns: config.ignore_patterns,
          context_lines: 15,
          platform: :ios,
          swift_functions: config.swift_functions
        )
      end
    end

    it 'prints a diff-specific message when source-mode diff filtering finds no entries' do
      Dir.mktmpdir do |source_dir|
        config = I18nContextGenerator::Config.new(
          translations: [],
          source_paths: [source_dir],
          discovery_mode: 'source',
          diff_base: 'origin/main'
        )
        extractor = described_class.new(config)
        git_diff = instance_double(I18nContextGenerator::GitDiff, changed_lines: { 'Sources/View.swift' => Set[10] })

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)
        allow(extractor).to receive(:searcher).and_return(
          instance_double(I18nContextGenerator::Searcher, discover_localization_entries: [])
        )

        expect { extractor.run }
          .to output("No changed source localization entries found in origin/main...HEAD.\n").to_stdout
      end
    end

    it 'prints one message when translation diff filtering finds no entries' do
      Dir.mktmpdir do |dir|
        translation_path = File.join(dir, 'Localizable.strings')
        File.write(translation_path, "\"settings.title\" = \"Settings\";\n")
        config = I18nContextGenerator::Config.new(
          translations: [translation_path],
          diff_base: 'origin/main'
        )
        extractor = described_class.new(config)
        git_diff = instance_double(I18nContextGenerator::GitDiff, changed_key_locations: {})

        allow(I18nContextGenerator::GitDiff).to receive(:new)
          .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)

        expect { extractor.run }
          .to output("No changed translation keys found in origin/main...HEAD.\n").to_stdout
      end
    end

    it 'checks source usage without constructing an LLM client' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: [ios_fixtures_path],
        discovery_mode: 'source',
        workflow_stage: 'check'
      )
      extractor = described_class.new(config)
      entry = I18nContextGenerator::Parsers::TranslationEntry.new(
        key: 'settings.title',
        text: 'Settings',
        source_file: nil
      )
      searcher = instance_double(I18nContextGenerator::Searcher)
      source_match = I18nContextGenerator::Searcher::Match.new(
        file: 'Settings.swift',
        line: 3,
        match_line: 'Text("settings.title")'
      )
      allow(searcher).to receive(:search).with('settings.title', resource_type: nil).and_return([source_match])
      allow(extractor).to receive(:load_entries).and_return([entry])
      extractor.instance_variable_set(:@searcher, searcher)
      allow(I18nContextGenerator::LLM::Client).to receive(:for)

      expect { extractor.run }
        .to output(/Check passed: 1 entries parsed; 0 without source usage/).to_stdout
      expect(I18nContextGenerator::LLM::Client).not_to have_received(:for)
    end

    it 'plans selected entries without processing them' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: [ios_fixtures_path],
        discovery_mode: 'source',
        workflow_stage: 'plan'
      )
      extractor = described_class.new(config)
      entry = I18nContextGenerator::Parsers::TranslationEntry.new(
        key: 'settings.title',
        text: 'Settings',
        source_file: nil
      )
      allow(extractor).to receive(:load_entries).and_return([entry])
      allow(extractor).to receive(:process_entries)

      expect { extractor.run }
        .to output(/Plan - would process these keys:.*settings\.title.*Destinations: none/m).to_stdout
      expect(extractor).not_to have_received(:process_entries)
    end
  end

  describe 'preview-diff workflow' do
    it 'renders translation write-back without modifying the translation file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, "\"settings.title\" = \"Settings\";\n")
        original = File.binread(path)
        config = I18nContextGenerator::Config.new(
          translations: [path],
          source_paths: [dir],
          workflow_stage: 'preview_diff',
          write_back: true
        )
        extractor = described_class.new(config)
        extractor.results << described_class::ExtractionResult.new(
          key: 'settings.title',
          text: 'Settings',
          description: 'Settings screen title',
          source_file: path
        )

        expect { extractor.send(:preview_changes) }
          .to output(%r{diff --git.*Localizable\.strings.*\+/\* Context: Settings screen title \*/}m).to_stdout
        expect(File.binread(path)).to eq(original)
      end
    end

    it 'does not write configured structured output while previewing' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        output_path = File.join(dir, 'context.csv')
        File.write(path, "\"settings.title\" = \"Settings\";\n")
        config = I18nContextGenerator::Config.new(
          translations: [path],
          source_paths: [dir],
          workflow_stage: 'preview_diff',
          write_back: true,
          output_path: output_path
        )
        extractor = described_class.new(config)
        extractor.results << described_class::ExtractionResult.new(
          key: 'settings.title',
          text: 'Settings',
          description: 'Settings screen title',
          source_file: path
        )

        expect { extractor.send(:deliver_results) }
          .to output(/\Adiff --git.*Settings screen title/m).to_stdout
        expect(File).not_to exist(output_path)
      end
    end

    it 'sends preview diagnostics and metrics to stderr' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        workflow_stage: 'preview_diff',
        write_back_to_code: true
      )
      extractor = described_class.new(config)

      expect { extractor.send(:log, 'Requests: 3, retries: 2') }
        .to output('').to_stdout
        .and output(/Requests: 3, retries: 2/).to_stderr
    end
  end

  describe '#log_metrics' do
    it 'labels estimated cost with its standard-price date' do
      output = StringIO.new
      extractor = described_class.new(
        I18nContextGenerator::Config.new(translations: [], provider: 'openai'),
        log_output: output
      )
      result = described_class::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Settings title',
        input_tokens: 200,
        output_tokens: 40,
        request_count: 1
      )
      extractor.instance_variable_set(
        :@metrics,
        I18nContextGenerator::RunMetrics.from(
          [result],
          provider: 'openai',
          model: 'gpt-5-mini'
        )
      )

      extractor.send(:log_metrics)

      expect(output.string).to include(
        'estimated cost: $0.000130',
        "standard list prices as of #{I18nContextGenerator::RUN_METRICS_PRICING_AS_OF}"
      )
    end
  end

  describe '#load_source_entries' do
    it 'hydrates source-discovered entries from translations when available' do
      config = I18nContextGenerator::Config.new(
        translations: ['Localizable.strings'],
        source_paths: ['Sources/'],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entries = [
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'SettingsViewController.swift',
          line: 12,
          text: nil,
          comment: 'Navigation title in code'
        )
      ]
      translation_entries = [
        build_entry('settings.title', 'Settings', metadata: { comment: 'Shown in settings screen' })
      ]
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: discovered_entries)

      allow(extractor).to receive_messages(
        searcher: searcher,
        load_translations: translation_entries
      )

      entries = extractor.send(:load_source_entries)

      expect(entries).to contain_exactly(
        have_attributes(
          key: 'settings.title',
          text: 'Settings',
          source_file: 'test.strings',
          metadata: {
            comment: 'Shown in settings screen',
            source_location: 'SettingsViewController.swift:12',
            source_locations: ['SettingsViewController.swift:12'],
            source_location_groups: [['SettingsViewController.swift:12']]
          }
        )
      )
    end

    it 'hydrates every source-scoped translation with the same key' do
      config = I18nContextGenerator::Config.new(
        translations: %w[english.strings french.strings],
        source_paths: ['Sources/'],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entry = I18nContextGenerator::Searcher::DiscoveredLocalization.new(
        key: 'settings.title',
        file: 'SettingsView.swift',
        line: 12
      )
      translations = [
        build_entry('settings.title', 'Settings', source_file: 'english.strings'),
        build_entry('settings.title', 'Réglages', source_file: 'french.strings')
      ]
      searcher = instance_double(
        I18nContextGenerator::Searcher,
        discover_localization_entries: [discovered_entry]
      )

      allow(extractor).to receive_messages(searcher: searcher, load_translations: translations)

      entries = extractor.send(:load_source_entries)

      expect(entries.map { |entry| [entry.source_file, entry.text] }).to eq(
        [['english.strings', 'Settings'], ['french.strings', 'Réglages']]
      )
    end

    it 'falls back to source text and comments when no translation entry exists' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: ['Sources/'],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entries = [
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'Save changes',
          file: 'EditorViewController.swift',
          line: 18,
          text: 'Save changes',
          comment: 'Button title in the editor'
        )
      ]
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: discovered_entries)

      allow(extractor).to receive(:searcher).and_return(searcher)

      entries = extractor.send(:load_source_entries)

      expect(entries).to contain_exactly(
        have_attributes(
          key: 'Save changes',
          text: 'Save changes',
          source_file: nil,
          metadata: {
            comment: 'Button title in the editor',
            source_location: 'EditorViewController.swift:18',
            source_locations: ['EditorViewController.swift:18'],
            source_location_groups: [['EditorViewController.swift:18']]
          }
        )
      )
    end

    it 'expands discovered Android plural and array resources to their translation children' do
      config = I18nContextGenerator::Config.new(
        translations: ['strings.xml'],
        source_paths: ['Sources/'],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entries = [
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'likes',
          file: 'Post.kt',
          line: 10,
          resource_type: :plural
        ),
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'days',
          file: 'Calendar.kt',
          line: 20,
          resource_type: :array
        )
      ]
      translation_entries = [
        build_entry('likes:one', '%d like', metadata: { plural: 'likes', quantity: 'one' }),
        build_entry('likes:other', '%d likes', metadata: { plural: 'likes', quantity: 'other' }),
        build_entry('days[0]', 'Monday', metadata: { array: 'days', index: 0 })
      ]
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: discovered_entries)

      allow(extractor).to receive_messages(searcher: searcher, load_translations: translation_entries)

      entries = extractor.send(:load_source_entries)

      expect(entries.map(&:key)).to eq(%w[likes:one likes:other days[0]])
      expect(entries.map { |entry| entry.metadata[:resource_type] }).to eq(%i[plural plural array])
      expect(entries.map { |entry| entry.metadata[:source_location] })
        .to eq(['Post.kt:10', 'Post.kt:10', 'Calendar.kt:20'])
    end

    it 'keeps resource type metadata for source-only Android collections' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: ['Sources/'],
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entry = I18nContextGenerator::Searcher::DiscoveredLocalization.new(
        key: 'likes',
        file: 'Post.kt',
        line: 10,
        resource_type: :plural
      )
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: [discovered_entry])

      allow(extractor).to receive(:searcher).and_return(searcher)

      entry = extractor.send(:load_source_entries).first

      expect(entry).to have_attributes(key: 'likes', text: 'likes')
      expect(entry.metadata).to include(resource_type: :plural, source_location: 'Post.kt:10')
    end

    it 'filters source-discovered entries by the configured source line filter' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: ['Sources/'],
        source_line_filter: { 'Sources/SettingsView.swift' => [12] },
        discovery_mode: 'source'
      )
      extractor = described_class.new(config)
      discovered_entries = [
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'Sources/SettingsView.swift',
          line: 12,
          text: 'Settings',
          comment: 'Visible title'
        ),
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'settings.subtitle',
          file: 'Sources/SettingsView.swift',
          line: 18,
          text: 'Manage store',
          comment: 'Visible subtitle'
        )
      ]
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: discovered_entries)

      allow(extractor).to receive(:searcher).and_return(searcher)

      entries = extractor.send(:load_source_entries)

      expect(entries).to contain_exactly(
        have_attributes(
          key: 'settings.title',
          text: 'Settings',
          metadata: {
            comment: 'Visible title',
            source_location: 'Sources/SettingsView.swift:12',
            source_locations: ['Sources/SettingsView.swift:12'],
            source_location_groups: [['Sources/SettingsView.swift:12']]
          }
        )
      )
    end

    it 'filters source-discovered entries by git diff line numbers in source mode' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: ['Sources/'],
        discovery_mode: 'source',
        diff_base: 'origin/main'
      )
      extractor = described_class.new(config)
      discovered_entries = [
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'Sources/SettingsView.swift',
          line: 12,
          text: 'Settings',
          comment: 'Visible title'
        ),
        I18nContextGenerator::Searcher::DiscoveredLocalization.new(
          key: 'settings.subtitle',
          file: 'Sources/SettingsView.swift',
          line: 18,
          text: 'Manage store',
          comment: 'Visible subtitle'
        )
      ]
      searcher = instance_double(I18nContextGenerator::Searcher, discover_localization_entries: discovered_entries)
      git_diff = instance_double(I18nContextGenerator::GitDiff, changed_lines: { 'Sources/SettingsView.swift' => Set[18] })

      allow(extractor).to receive(:searcher).and_return(searcher)
      allow(I18nContextGenerator::GitDiff).to receive(:new)
        .with(base_ref: 'origin/main', head_ref: 'HEAD').and_return(git_diff)

      entries = extractor.send(:load_source_entries)

      expect(entries).to contain_exactly(
        have_attributes(
          key: 'settings.subtitle',
          text: 'Manage store',
          metadata: {
            comment: 'Visible subtitle',
            source_location: 'Sources/SettingsView.swift:18',
            source_locations: ['Sources/SettingsView.swift:18'],
            source_location_groups: [['Sources/SettingsView.swift:18']]
          }
        )
      )
    end

    it 'keeps a deduplicated key when any evidence location changed' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: ['Sources/'],
        discovery_mode: 'source',
        source_line_filter: { 'Sources/First.swift' => [10] }
      )
      extractor = described_class.new(config)
      discovered_entry = I18nContextGenerator::Searcher::DiscoveredLocalization.new(
        key: 'settings.title',
        file: 'Sources/Preferred.swift',
        line: 30,
        comment: 'Preferred comment',
        locations: ['Sources/First.swift:10', 'Sources/Preferred.swift:30']
      )
      searcher = instance_double(
        I18nContextGenerator::Searcher,
        discover_localization_entries: [discovered_entry]
      )

      allow(extractor).to receive(:searcher).and_return(searcher)

      entry = extractor.send(:load_source_entries).first

      expect(entry.metadata[:source_locations]).to eq(
        ['Sources/First.swift:10', 'Sources/Preferred.swift:30']
      )
      expect(entry.metadata[:source_location_groups]).to eq(
        [['Sources/First.swift:10', 'Sources/Preferred.swift:30']]
      )
    end
  end

  describe '#process_entry' do
    let(:config) do
      I18nContextGenerator::Config.new(
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
      searcher = instance_double(I18nContextGenerator::Searcher, search: [])

      allow(extractor).to receive(:searcher).and_return(searcher)

      result = extractor.send(:process_entry, entry)

      expect(result.description).to eq('No usage found in source code')
      expect(result.status).to eq(:no_usage)
      expect(result).not_to be_actionable
      expect(result.locations).to eq([])
      expect(result.error).to be_nil
    end

    it 'limits matches, forwards translation comments, and caches the result' do
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one, match_two, match_three])
      cache = instance_double(I18nContextGenerator::Cache)
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)
      llm_result = I18nContextGenerator::LLM::ContextResult.new(
        description: 'Navigation title for the settings screen',
        ui_element: 'title',
        tone: 'neutral',
        max_length: 20
      )

      allow(cache).to receive(:get).and_return(nil)
      allow(llm).to receive(:generate_context).and_return(llm_result)
      cache_write = nil
      allow(cache).to receive(:set) do |key, text, result, context:|
        cache_write = { key: key, text: text, result: result, context: context }
      end

      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      result = extractor.send(:process_entry, entry)

      expect(llm).to have_received(:generate_context).with(
        key: 'settings.title',
        text: 'Settings',
        matches: [match_one, match_two],
        model: 'gpt-5-mini',
        comment: 'Shown in the settings navigation bar',
        include_file_paths: false,
        redact_prompts: true,
        max_prompt_chars: 50_000
      )
      expect(cache_write[:key]).to eq('settings.title')
      expect(cache_write[:text]).to eq('Settings')
      expect(cache_write[:result][:description]).to eq('Navigation title for the settings screen')
      cache_identity = JSON.parse(cache_write[:context])
      expect(cache_identity).to include(
        'comment' => 'Shown in the settings navigation bar',
        'provider' => 'anthropic',
        'resolved_model' => 'gpt-5-mini'
      )
      expect(cache_identity['prompt']).to eq(
        'include_file_paths' => false,
        'redact_prompts' => true,
        'max_prompt_chars' => 50_000
      )
      expect(result.description).to eq('Navigation title for the settings screen')
      expect(result.locations).to eq(
        ['/tmp/SettingsViewController.swift:10', '/tmp/SettingsHeaderView.swift:18']
      )
    end

    it 'does not cache rate-limit, transport, or parse failures so later runs can retry them' do
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(I18nContextGenerator::Cache, get: nil)
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)
      llm_results = [
        I18nContextGenerator::LLM::ContextResult.new(
          description: 'Rate limited',
          error: 'Rate limit exceeded'
        ),
        I18nContextGenerator::LLM::ContextResult.new(
          description: 'API request failed',
          error: 'Request timed out'
        ),
        I18nContextGenerator::LLM::ContextResult.new(
          description: 'Failed to parse response',
          error: 'Response did not contain a valid JSON object'
        )
      ]

      allow(cache).to receive(:set)
      allow(llm).to receive(:generate_context).and_return(*llm_results)
      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      results = llm_results.map { extractor.send(:process_entry, entry) }

      expect(results.map(&:error)).to eq(llm_results.map(&:error))
      expect(cache).not_to have_received(:set)
    end

    it 'returns all discovery evidence locations ahead of later usage matches' do
      source_entry = build_entry(
        'settings.title',
        'Settings',
        metadata: {
          comment: 'Shown in the settings navigation bar',
          source_location: '/tmp/SettingsView.swift:14',
          source_locations: ['/tmp/FirstSettingsView.swift:8', '/tmp/SettingsView.swift:14']
        }
      )
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(I18nContextGenerator::Cache, get: nil, set: nil)
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)

      allow(llm).to receive(:generate_context).and_return(
        I18nContextGenerator::LLM::ContextResult.new(description: 'Settings title')
      )

      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      result = extractor.send(:process_entry, source_entry)

      expect(result.locations).to eq(['/tmp/FirstSettingsView.swift:8', '/tmp/SettingsView.swift:14'])
    end

    it 'includes source discovery, resolved model, and custom endpoint in cache identity' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        provider: 'openai_compatible',
        model: 'local-model',
        endpoint: 'http://127.0.0.1:11434/v1/responses'
      )
      extractor = described_class.new(config)
      source_entry = build_entry(
        'settings.title',
        'Settings',
        metadata: {
          source_location: '/tmp/SettingsView.swift:14',
          source_locations: ['/tmp/SettingsView.swift:14']
        }
      )
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache_context = nil
      cache = instance_double(I18nContextGenerator::Cache, set: nil)
      allow(cache).to receive(:get) do |_key, _text, context:|
        cache_context = context
        nil
      end
      llm = instance_double(I18nContextGenerator::LLM::OpenAICompatible)
      allow(llm).to receive(:generate_context).and_return(
        I18nContextGenerator::LLM::ContextResult.new(description: 'Settings title')
      )
      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      extractor.send(:process_entry, source_entry)
      identity = JSON.parse(cache_context)

      expect(identity['resolved_model']).to eq('local-model')
      expect(identity['endpoint']).to eq('http://127.0.0.1:11434/v1/responses')
      expect(identity.dig('source_discovery', 'source_location')).to eq('/tmp/SettingsView.swift:14')
      expect(identity.dig('source_discovery', 'source_locations')).to eq(['/tmp/SettingsView.swift:14'])
    end

    it 'separates changed discovery locations from all evidence locations' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        discovery_mode: :source,
        source_line_filter: {
          'Sources/FirstSettingsView.swift' => [8, 9],
          'Sources/SettingsView.swift' => [14]
        }
      )
      extractor = described_class.new(config)
      source_entry = build_entry(
        'settings.title',
        'Settings',
        metadata: {
          source_locations: [
            './Sources/FirstSettingsView.swift:8',
            './Sources/FirstSettingsView.swift:9',
            './Sources/SettingsView.swift:14'
          ],
          source_location_groups: [
            ['./Sources/FirstSettingsView.swift:8', './Sources/FirstSettingsView.swift:9'],
            ['./Sources/SettingsView.swift:14']
          ]
        }
      )
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(I18nContextGenerator::Cache, get: nil, set: nil)
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)

      allow(llm).to receive(:generate_context).and_return(
        I18nContextGenerator::LLM::ContextResult.new(description: 'Settings title')
      )
      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      result = extractor.send(:process_entry, source_entry)

      expect(
        [result.locations, result.changed_locations, result.changed_location_groups]
      ).to eq(
        [
          [
            './Sources/FirstSettingsView.swift:8',
            './Sources/FirstSettingsView.swift:9',
            './Sources/SettingsView.swift:14'
          ],
          [
            './Sources/FirstSettingsView.swift:8',
            './Sources/FirstSettingsView.swift:9',
            './Sources/SettingsView.swift:14'
          ],
          [
            ['./Sources/FirstSettingsView.swift:8', './Sources/FirstSettingsView.swift:9'],
            ['./Sources/SettingsView.swift:14']
          ]
        ]
      )
    end

    it 'omits translation comments when the config disables them' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        include_translation_comments: false
      )
      extractor = described_class.new(config)
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(I18nContextGenerator::Cache, get: nil, set: nil)
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)

      allow(llm).to receive(:generate_context).and_return(
        I18nContextGenerator::LLM::ContextResult.new(description: 'Settings title')
      )

      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      extractor.send(:process_entry, entry)

      expect(llm).to have_received(:generate_context).with(hash_including(comment: nil))
    end

    it 'returns cached results without calling the llm again' do
      cached_config = I18nContextGenerator::Config.new(
        translations: [],
        source_line_filter: { '/tmp/SettingsViewController.swift' => [10] }
      )
      cached_extractor = described_class.new(cached_config)
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(
        I18nContextGenerator::Cache,
        get: {
          'key' => 'settings.title',
          'text' => 'Settings',
          'description' => 'Cached description',
          'locations' => ['stale.swift:99'],
          'status' => 'success'
        }
      )
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)

      allow(llm).to receive(:generate_context)
      allow(cached_extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      result = cached_extractor.send(:process_entry, entry)

      expect(llm).not_to have_received(:generate_context)
      expect(result.description).to eq('Cached description')
      expect(result.status).to eq(:success)
      expect(result).to be_actionable
      expect(result.locations).to eq(['/tmp/SettingsViewController.swift:10'])
      expect(result.changed_locations).to eq(['/tmp/SettingsViewController.swift:10'])
    end

    it 'ignores cached failures and calls the llm again' do
      searcher = instance_double(I18nContextGenerator::Searcher, search: [match_one])
      cache = instance_double(
        I18nContextGenerator::Cache,
        get: {
          'key' => 'settings.title',
          'text' => 'Settings',
          'description' => 'API request failed',
          'locations' => [],
          'error' => 'timeout'
        },
        set: nil
      )
      llm = instance_double(I18nContextGenerator::LLM::OpenAI)
      allow(llm).to receive(:generate_context).and_return(
        I18nContextGenerator::LLM::ContextResult.new(description: 'Fresh description')
      )
      allow(extractor).to receive_messages(searcher: searcher, cache: cache, llm: llm)

      result = extractor.send(:process_entry, entry)

      expect(llm).to have_received(:generate_context)
      expect(result.description).to eq('Fresh description')
      expect(result.error).to be_nil
    end
  end

  describe '#process_entries' do
    it 'initializes diff-backed source locations before starting worker threads' do
      main_thread = Thread.current
      observed_threads = Concurrent::Array.new
      config = I18nContextGenerator::Config.new(
        translations: ['Localizable.strings'],
        source_paths: ['Sources'],
        diff_base: 'main',
        concurrency: 3
      )
      extractor = described_class.new(config)
      git_diff = instance_double(I18nContextGenerator::GitDiff)
      entries = (1..3).map { |index| build_entry("key.#{index}", "Text #{index}") }

      allow(git_diff).to receive(:changed_lines) do
        observed_threads << Thread.current
        { 'Sources/View.swift' => Set[10] }
      end
      allow(extractor).to receive(:git_diff).and_return(git_diff)
      allow(extractor).to receive(:process_entry) do |entry|
        extractor.send(:source_line_filter)
        I18nContextGenerator::ContextExtractor::ExtractionResult.new(
          key: entry.key,
          text: entry.text,
          description: 'Context'
        )
      end

      extractor.send(:process_entries, entries)

      expect(observed_threads).to eq([main_thread])
      expect(git_diff).to have_received(:changed_lines).once
    end
  end

  describe '#write_back_to_code' do
    it 'skips ignored Swift files' do
      Dir.mktmpdir do |dir|
        pods_dir = File.join(dir, 'Pods')
        app_dir = File.join(dir, 'App')
        ignored_file = File.join(pods_dir, 'Ignored.swift')
        app_file = File.join(app_dir, 'Main.swift')

        FileUtils.mkdir_p(pods_dir)
        FileUtils.mkdir_p(app_dir)
        File.write(ignored_file, 'let title = NSLocalizedString("settings.title", comment: "old")')
        File.write(app_file, 'let title = NSLocalizedString("settings.title", comment: "old")')

        config = I18nContextGenerator::Config.new(
          translations: [],
          source_paths: [dir],
          ignore_patterns: ['**/Pods/**'],
          write_back_to_code: true
        )
        extractor = described_class.new(config)
        extractor.results << described_class::ExtractionResult.new(
          key: 'settings.title',
          text: 'Settings',
          description: 'Updated context'
        )

        extractor.send(:write_back_to_code)

        expect(File.read(ignored_file)).to include('comment: "old"')
        expect(File.read(app_file)).to include('comment: "Context: Updated context"')
      end
    end
  end

  describe '#load_translations' do
    it 'passes per-file locale configuration to the parser' do
      Dir.mktmpdir do |dir|
        existing = File.join(dir, 'translations.yml')
        File.write(existing, "en:\n  settings:\n    title: Settings\n")

        config = I18nContextGenerator::Config.new(
          translations: [existing],
          translation_locales: { existing => 'en' }
        )
        extractor = described_class.new(config)
        parser = instance_double(
          I18nContextGenerator::Parsers::YamlParser,
          parse: [build_entry('settings.title', 'Settings')]
        )

        allow(I18nContextGenerator::Parsers::Base).to receive(:for).with(existing, locale: 'en').and_return(parser)

        result = extractor.send(:load_translations)

        expect(result.map(&:key)).to eq(['settings.title'])
      end
    end

    it 'preserves configured file and parser order, including cross-file duplicate keys' do
      Dir.mktmpdir do |dir|
        second_path = File.join(dir, 'second.json')
        first_path = File.join(dir, 'first.json')
        File.write(second_path, '{"second":"Second","shared":"Deuxième"}')
        File.write(first_path, '{"first":"First","shared":"Premier"}')
        config = I18nContextGenerator::Config.new(translations: [second_path, first_path])
        extractor = described_class.new(config)

        entries = extractor.send(:load_translations)

        expect(entries.map { |entry| [File.basename(entry.source_file), entry.key] }).to eq(
          [['second.json', 'second'], ['second.json', 'shared'], ['first.json', 'first'], ['first.json', 'shared']]
        )
      end
    end

    it 'deduplicates identical source keys and rejects conflicting values in one file' do
      config = I18nContextGenerator::Config.new(translations: [])
      extractor = described_class.new(config)
      duplicate_entries = [
        build_entry('shared', 'Same', source_file: 'same.strings'),
        build_entry('shared', 'Same', source_file: 'same.strings')
      ]

      expect(extractor.send(:validate_translation_entries, duplicate_entries).size).to eq(1)

      conflicting_entries = duplicate_entries + [
        build_entry('shared', 'Different', source_file: 'same.strings')
      ]
      expect { extractor.send(:validate_translation_entries, conflicting_entries) }
        .to raise_error(I18nContextGenerator::Error, /Conflicting duplicate translation keys.*same\.strings:shared/)
    end

    it 'rejects structurally invalid parser entries' do
      config = I18nContextGenerator::Config.new(translations: [])
      extractor = described_class.new(config)
      invalid_entry = I18nContextGenerator::Parsers::TranslationEntry.new(
        key: nil,
        text: 'Missing key',
        source_file: 'strings.xml'
      )

      expect { extractor.send(:validate_translation_entries, [invalid_entry]) }
        .to raise_error(I18nContextGenerator::Error, /Invalid translation entry in strings\.xml/)
    end
  end

  describe '#write_output' do
    it 'uses the JSON writer for json output' do
      config = I18nContextGenerator::Config.new(translations: [], output_path: 'out.json', output_format: 'json')
      extractor = described_class.new(config)
      writer = instance_double(I18nContextGenerator::Writers::JsonWriter, write: nil)

      allow(I18nContextGenerator::Writers::JsonWriter).to receive(:new).and_return(writer)
      extractor.results << build_result('settings.title', 'Settings title')

      extractor.send(:write_output)

      expect(writer).to have_received(:write).with(
        extractor.results,
        'out.json',
        metrics: extractor.metrics,
        output: $stdout
      )
    end

    it 'uses the CSV writer for non-json output' do
      config = I18nContextGenerator::Config.new(translations: [], output_path: 'out.csv', output_format: 'csv')
      extractor = described_class.new(config)
      writer = instance_double(I18nContextGenerator::Writers::CsvWriter, write: nil)

      allow(I18nContextGenerator::Writers::CsvWriter).to receive(:new).and_return(writer)
      extractor.results << build_result('settings.title', 'Settings title')

      extractor.send(:write_output)

      expect(writer).to have_received(:write).with(
        extractor.results,
        'out.csv',
        metrics: extractor.metrics,
        output: $stdout
      )
    end
  end

  describe 'structured stdout delivery' do
    it 'keeps machine output on stdout and diagnostics on stderr' do
      config = I18nContextGenerator::Config.new(
        translations: [],
        output_stdout: true,
        output_format: 'json'
      )
      extractor = described_class.new(config)
      extractor.results << described_class::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Settings title'
      )

      expect { extractor.send(:deliver_results) }
        .to output(/\A\{.*"settings.title".*\}\n\z/m).to_stdout
        .and output(/Wrote 1 results to stdout/).to_stderr
    end

    it 'supports injected machine and diagnostic streams' do
      structured_output = StringIO.new
      log_output = StringIO.new
      config = I18nContextGenerator::Config.new(
        translations: [],
        output_stdout: true,
        output_format: 'json'
      )
      extractor = described_class.new(
        config,
        structured_output: structured_output,
        log_output: log_output,
        quiet: true,
        progress: false
      )
      extractor.results << described_class::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Settings title'
      )

      extractor.send(:deliver_results)

      expect(Oj.load(structured_output.string).dig('entries', 0, 'key')).to eq('settings.title')
      expect(log_output.string).to be_empty
      expect(extractor.send(:build_progress, 1)).to be_nil
    end
  end

  describe '#source_writer_for' do
    let(:extractor) { described_class.new(I18nContextGenerator::Config.new(translations: [])) }

    it 'selects the strings writer for .strings files' do
      expect(extractor.send(:source_writer_for, 'ios/Localizable.strings'))
        .to be_a(I18nContextGenerator::Writers::StringsWriter)
    end

    it 'selects the string-catalog writer for .xcstrings files' do
      expect(extractor.send(:source_writer_for, 'ios/Localizable.xcstrings'))
        .to be_a(I18nContextGenerator::Writers::XcstringsWriter)
    end

    it 'selects the Android XML writer for Android string resources' do
      expect(extractor.send(:source_writer_for, 'android/res/values/strings.xml'))
        .to be_a(I18nContextGenerator::Writers::AndroidXmlWriter)
    end

    it 'returns nil for unsupported XML files' do
      expect(extractor.send(:source_writer_for, 'android/res/layout/activity_main.xml')).to be_nil
    end
  end

  describe '#truncate' do
    let(:extractor) do
      config = I18nContextGenerator::Config.new(translations: [])
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

  def build_entry(key, text, metadata: nil, source_file: 'test.strings')
    I18nContextGenerator::Parsers::TranslationEntry.new(
      key: key,
      text: text,
      source_file: source_file,
      metadata: metadata
    )
  end

  def build_match(file:, line:, match_line:, context:, enclosing_scope:)
    I18nContextGenerator::Searcher::Match.new(
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
