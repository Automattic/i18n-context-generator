# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Config do
  describe '#initialize' do
    it 'sets default values' do
      config = described_class.new

      expect(config.translations).to eq([])
      expect(config.source_paths).to eq(['.'])
      expect(config.ignore_patterns).to eq(described_class.default_ignore_patterns)
      expect(config.provider).to eq('anthropic')
      expect(config.concurrency).to eq(5)
      expect(config.context_lines).to eq(15)
      expect(config.max_matches_per_key).to eq(3)
      expect(config.max_prompt_chars).to eq(50_000)
      expect(config.output_path).to be_nil
      expect(config.output_format).to eq('csv')
      expect(config.no_cache).to be true
      expect(config.cache_dir).to eq('.i18n-context-generator-cache')
      expect(config.dry_run).to be false
      expect(config.write_back).to be false
      expect(config.context_prefix).to eq('Context: ')
      expect(config.context_mode).to eq('replace')
      expect(config.include_file_paths).to be false
      expect(config.include_translation_comments).to be true
      expect(config.redact_prompts).to be true
      expect(config.discovery_mode).to eq('auto')
      expect(config.platform).to be_nil
      expect(config.diff_head).to eq('HEAD')
      expect(config.translation_locales).to eq({})
      expect(config.context_files).to eq([])
      expect(config.supplemental_context).to eq({})
      expect(config.swift_functions).to include('NSLocalizedString', 'String(localized:', 'Text(')
    end

    it 'accepts custom values' do
      config = described_class.new(
        translations: ['/path/to/file.strings'],
        source_paths: ['/path/to/sources'],
        concurrency: 10,
        output_path: 'output.csv',
        no_cache: false,
        dry_run: true,
        context_prefix: '',
        context_files: %w[GLOSSARY.md localization-style.md],
        supplemental_context: { 'Pull request title' => 'Improve checkout labels' }
      )

      expect(config.translations).to eq(['/path/to/file.strings'])
      expect(config.source_paths).to eq(['/path/to/sources'])
      expect(config.concurrency).to eq(10)
      expect(config.output_path).to eq('output.csv')
      expect(config.no_cache).to be false
      expect(config.dry_run).to be true
      expect(config.context_prefix).to eq('')
      expect(config.context_files).to eq(%w[GLOSSARY.md localization-style.md])
      expect(config.supplemental_context).to eq('Pull request title' => 'Improve checkout labels')
    end

    it 'adds custom Swift functions without removing the built-in syntaxes' do
      config = described_class.new(swift_functions: %w[MyLocalizedString NSLocalizedString])

      expect(config.swift_functions).to eq(
        [
          'NSLocalizedString',
          'String(localized:',
          'Text(',
          'LocalizedStringResource(',
          'MyLocalizedString'
        ]
      )
    end

    it 'allows nil output_path' do
      config = described_class.new(output_path: nil)

      expect(config.output_path).to be_nil
    end

    it 'treats explicit nil as missing for defaulted non-boolean values' do
      config = described_class.new(
        translations: nil,
        source_paths: nil,
        ignore_patterns: nil,
        provider: nil,
        concurrency: nil,
        context_lines: nil,
        max_matches_per_key: nil,
        output_format: nil,
        swift_functions: nil,
        context_prefix: nil,
        context_mode: nil,
        discovery_mode: nil,
        context_files: nil,
        supplemental_context: nil
      )

      expect(config.translations).to eq([])
      expect(config.source_paths).to eq(['.'])
      expect(config.ignore_patterns).to eq(described_class.default_ignore_patterns)
      expect(config.provider).to eq('anthropic')
      expect(config.concurrency).to eq(5)
      expect(config.context_lines).to eq(15)
      expect(config.max_matches_per_key).to eq(3)
      expect(config.output_format).to eq('csv')
      expect(config.swift_functions).to include('NSLocalizedString', 'String(localized:', 'Text(')
      expect(config.context_prefix).to eq('Context: ')
      expect(config.context_mode).to eq('replace')
      expect(config.discovery_mode).to eq('auto')
      expect(config.context_files).to eq([])
      expect(config.supplemental_context).to eq({})
    end

    it 'preserves explicit false for booleans while defaulting nil booleans' do
      config = described_class.new(
        no_cache: false,
        dry_run: false,
        write_back: false,
        write_back_to_code: false,
        include_file_paths: false,
        include_translation_comments: nil,
        redact_prompts: nil
      )

      expect(config.no_cache).to be false
      expect(config.dry_run).to be false
      expect(config.write_back).to be false
      expect(config.write_back_to_code).to be false
      expect(config.include_file_paths).to be false
      expect(config.include_translation_comments).to be true
      expect(config.redact_prompts).to be true
    end

    it 'normalizes enum-like Ruby API values to strings' do
      config = described_class.new(
        provider: :openai,
        output_format: :json,
        context_mode: :append,
        discovery_mode: :source,
        platform: :ios,
        diff_base: 'danger_base',
        diff_head: 'danger_head'
      )

      expect(config).to have_attributes(
        provider: 'openai',
        output_format: 'json',
        context_mode: 'append',
        discovery_mode: 'source',
        platform: 'ios',
        diff_base: 'danger_base',
        diff_head: 'danger_head'
      )
      expect { config.validate! }.not_to raise_error
    end
  end

  describe '.from_file' do
    let(:yaml_content) do
      <<~YAML
        translations:
          - path/to/Localizable.strings
          - path/to/strings.xml

        source:
          paths:
            - ./Sources
            - ./App
          ignore:
            - "**/Generated/**"
            - "**/*.test.swift"

        llm:
          provider: anthropic
          model: claude-3-haiku

        processing:
          discovery_mode: source
          concurrency: 8
          context_lines: 15
          max_matches_per_key: 5
          max_prompt_chars: 24000

        cache:
          enabled: true
          directory: tmp/i18n-cache

        output:
          path: context.csv
          format: csv
          write_back: true
          context_prefix: ""
          context_mode: append

        privacy:
          include_file_paths: true
          include_translation_comments: false
          redact_prompts: false

        context:
          files:
            - GLOSSARY.md
            - docs/localization-style.md

      YAML
    end

    let(:config_path) { File.join(Dir.tmpdir, 'test_i18n_context_generator.yml') }

    before do
      File.write(config_path, yaml_content)
    end

    after do
      FileUtils.rm_f(config_path)
    end

    it 'loads configuration from YAML file' do
      config = described_class.from_file(config_path)

      expect(config.translations).to eq(['path/to/Localizable.strings', 'path/to/strings.xml'])
      expect(config.source_paths).to eq(['./Sources', './App'])
      expect(config.ignore_patterns).to include(*described_class.default_ignore_patterns)
      expect(config.ignore_patterns).to include('**/Generated/**', '**/*.test.swift')
      expect(config.provider).to eq('anthropic')
      expect(config.model).to eq('claude-3-haiku')
      expect(config.discovery_mode).to eq('source')
      expect(config.concurrency).to eq(8)
      expect(config.context_lines).to eq(15)
      expect(config.max_matches_per_key).to eq(5)
      expect(config.max_prompt_chars).to eq(24_000)
      expect(config.no_cache).to be false
      expect(config.cache_dir).to eq('tmp/i18n-cache')
      expect(config.output_path).to eq('context.csv')
      expect(config.write_back).to be true
      expect(config.context_prefix).to eq('')
      expect(config.context_mode).to eq('append')
      expect(config.include_file_paths).to be true
      expect(config.include_translation_comments).to be false
      expect(config.redact_prompts).to be false
      expect(config.context_files).to eq(['GLOSSARY.md', 'docs/localization-style.md'])
      expect(config.supplemental_context).to eq({})
    end

    it 'handles translations as hash with path key' do
      yaml_with_hash = <<~YAML
        translations:
          - path: translations.yml
            locale: en
      YAML

      File.write(config_path, yaml_with_hash)
      config = described_class.from_file(config_path)

      expect(config.translations).to eq(['translations.yml'])
      expect(config.translation_locales).to eq('translations.yml' => 'en')
    end

    it 'infers output format from the configured output path when format is omitted' do
      File.write(config_path, "output:\n  path: context.json\n")

      expect(described_class.from_file(config_path).output_format).to eq('json')
    end

    it 'rejects conflicting locale declarations for one translation file' do
      File.write(config_path, <<~YAML)
        translations:
          - path: translations.yml
            locale: en
          - path: translations.yml
            locale: fr
      YAML

      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /Conflicting translation locales/)
    end

    it 'wraps malformed YAML and invalid section shapes in configuration errors' do
      File.write(config_path, "source:\n  paths: [\n")
      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /Invalid config YAML.*line/)

      File.write(config_path, "source: Sources\n")
      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /source must be a mapping/)
    end

    it 'rejects non-boolean cache enablement' do
      File.write(config_path, "cache:\n  enabled: sometimes\n")

      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /cache.enabled must be true or false/)
    end

    it 'wraps unsupported YAML aliases in a configuration error' do
      File.write(config_path, "defaults: &defaults\n  concurrency: 5\nprocessing: *defaults\n")

      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /Invalid config YAML.*Alias parsing was not enabled/)
    end

    it 'rejects a non-mapping document root' do
      File.write(config_path, "- invalid\n- root\n")

      expect { described_class.from_file(config_path) }
        .to raise_error(I18nContextGenerator::Error, /root must be a mapping/)
    end
  end

  describe '.load' do
    it 'reports a configured file that does not exist' do
      expect { described_class.load(config: '/missing/i18n.yml') }
        .to raise_error(I18nContextGenerator::Error, /Config file not found/)
    end
  end

  describe '.from_cli' do
    it 'combines repeatable singular list flags and accepts legacy comma-separated values' do
      config = described_class.from_cli(
        translation: %w[First.strings Second.strings],
        source: %w[Sources Features Shared],
        context_file: %w[GLOSSARY.md localization-style.md],
        key: ['settings.*', 'profile.title'],
        keys: 'legacy.one,legacy.two'
      )

      expect(config.translations).to eq(%w[First.strings Second.strings])
      expect(config.source_paths).to eq(%w[Sources Features Shared])
      expect(config.context_files).to eq(%w[GLOSSARY.md localization-style.md])
      expect(config.key_filter).to eq(%w[settings.* profile.title legacy.one legacy.two])
    end

    it 'preserves commas in singular path and key flags' do
      Dir.mktmpdir do |dir|
        translation = File.join(dir, 'Resources,Legacy.xcstrings')
        source = File.join(dir, 'Sources,Legacy')
        File.write(translation, '{}')
        FileUtils.mkdir_p(source)

        config = described_class.from_cli(
          translation: [translation],
          source: [source],
          key: ['greeting,formal']
        )

        expect(config.translations).to eq([translation])
        expect(config.source_paths).to eq([source])
        expect(config.key_filter).to eq(['greeting,formal'])
      end
    end

    it 'never infers a legacy list from a singular path flag' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.touch(%w[Resources Legacy.xcstrings])

          config = described_class.from_cli(
            translation: ['Resources,Legacy.xcstrings']
          )

          expect(config.translations).to eq(['Resources,Legacy.xcstrings'])
        end
      end
    end

    it 'parses CLI options' do
      options = {
        translations: 'file1.strings,file2.strings',
        source: ['./Sources', './App'],
        provider: 'anthropic',
        model: 'claude-3-opus',
        discovery_mode: 'source',
        concurrency: 3,
        max_prompt_chars: 18_000,
        output: 'output.csv',
        format: 'json',
        cache: true,
        cache_dir: 'tmp/context-cache',
        dry_run: true,
        keys: 'key1,key2',
        write_back: true,
        diff_base: 'origin/main',
        diff_head: 'feature/head',
        context_prefix: 'Note: ',
        context_mode: 'append',
        include_file_paths: true,
        include_translation_comments: false,
        redact_prompts: false,
        context_file: ['GLOSSARY.md', 'docs/localization-style.md']
      }

      config = described_class.from_cli(options)

      expect(config.translations).to eq(['file1.strings', 'file2.strings'])
      expect(config.source_paths).to eq(['./Sources', './App'])
      expect(config.provider).to eq('anthropic')
      expect(config.model).to eq('claude-3-opus')
      expect(config.discovery_mode).to eq('source')
      expect(config.concurrency).to eq(3)
      expect(config.max_prompt_chars).to eq(18_000)
      expect(config.output_path).to eq('output.csv')
      expect(config.output_format).to eq('json')
      expect(config.no_cache).to be false
      expect(config.cache_dir).to eq('tmp/context-cache')
      expect(config.dry_run).to be true
      expect(config.key_filter).to eq(%w[key1 key2])
      expect(config.write_back).to be true
      expect(config.diff_base).to eq('origin/main')
      expect(config.diff_head).to eq('feature/head')
      expect(config.context_prefix).to eq('Note: ')
      expect(config.context_mode).to eq('append')
      expect(config.include_file_paths).to be true
      expect(config.include_translation_comments).to be false
      expect(config.redact_prompts).to be false
      expect(config.context_files).to eq(['GLOSSARY.md', 'docs/localization-style.md'])
    end

    it 'uses defaults for missing options' do
      config = described_class.from_cli({})

      expect(config.translations).to eq([])
      expect(config.source_paths).to eq(['.'])
      expect(config.no_cache).to be true
      expect(config.dry_run).to be false
    end

    it 'infers JSON output from its extension when format is omitted' do
      config = described_class.from_cli(output: 'translation-context.json')

      expect(config.output_format).to eq('json')
    end
  end

  describe '#merge_cli' do
    let(:base_config) do
      described_class.new(
        translations: ['base.strings'],
        context_files: ['base-glossary.md'],
        output_path: 'base.csv',
        no_cache: false,
        concurrency: 5
      )
    end

    it 'overrides config with CLI options' do
      options = {
        output: 'override.csv',
        dry_run: true,
        concurrency: 10
      }

      merged = base_config.merge_cli(options)

      expect(merged.output_path).to eq('override.csv')
      expect(merged.dry_run).to be true
      expect(merged.concurrency).to eq(10)
      # Original values preserved when not overridden
      expect(merged.translations).to eq(['base.strings'])
    end

    it 'merges repeatable singular path and key flags over file configuration' do
      base_config.merge_cli(
        translation: %w[First.strings Second.strings],
        source: %w[Sources Shared],
        context_file: %w[GLOSSARY.md localization-style.md],
        key: %w[settings.* profile.title]
      )

      expect(base_config.translations).to eq(%w[First.strings Second.strings])
      expect(base_config.source_paths).to eq(%w[Sources Shared])
      expect(base_config.context_files).to eq(%w[GLOSSARY.md localization-style.md])
      expect(base_config.key_filter).to eq(%w[settings.* profile.title])
    end

    it 'normalizes a dash output override to structured stdout' do
      base_config.merge_cli(output: '-')

      expect(base_config.output_path).to eq('-')
      expect(base_config.output_stdout).to be(true)
    end

    it 'honors an explicit false stdout override' do
      config = described_class.new(output_stdout: true)

      config.merge_cli(stdout: false)

      expect(config.output_stdout).to be(false)
      expect(config.output_path).to be_nil
    end

    it 'returns self for chaining' do
      result = base_config.merge_cli({})

      expect(result).to be(base_config)
    end

    it 'can set boolean options to false' do
      config = described_class.new(dry_run: true, write_back: true)

      config.merge_cli(dry_run: false, write_back: false, redact_prompts: false)

      expect(config.dry_run).to be false
      expect(config.write_back).to be false
      expect(config.redact_prompts).to be false
    end

    it 'clears an inherited model when the provider changes without a model override' do
      config = described_class.new(provider: 'anthropic', model: 'claude-sonnet-4-6')

      config.merge_cli(provider: 'openai')

      expect(config.provider).to eq('openai')
      expect(config.model).to be_nil
    end

    it 'keeps or explicitly replaces the model when the provider is compatible' do
      config = described_class.new(provider: 'anthropic', model: 'claude-sonnet-4-6')

      config.merge_cli(provider: 'anthropic')
      expect(config.model).to eq('claude-sonnet-4-6')

      config.merge_cli(provider: 'openai', model: 'gpt-5-mini')
      expect(config.model).to eq('gpt-5-mini')
    end
  end

  describe '.default_ignore_patterns' do
    it 'includes common source, dependency, and test patterns to ignore' do
      patterns = described_class.default_ignore_patterns

      expect(patterns).to include('**/node_modules/**')
      expect(patterns).to include('**/vendor/**')
      expect(patterns).to include('**/.git/**')
      expect(patterns).to include('**/build/**')
      expect(patterns).to include('**/*.test.*')
      expect(patterns).to include('**/*.spec.*')
    end

    it 'includes iOS/Android dependency and test patterns' do
      patterns = described_class.default_ignore_patterns

      expect(patterns).to include('**/Pods/**')
      expect(patterns).to include('**/Carthage/**')
      expect(patterns).to include('**/.build/**')
      expect(patterns).to include('**/DerivedData/**')
      expect(patterns).to include('**/*Tests.swift')
      expect(patterns).to include('**/*Tests.kt')
      expect(patterns).to include('**/*Test.java')
      expect(patterns).to include('**/*Test.kt')
    end
  end

  describe '#validate!' do
    it 'returns itself for a valid configuration' do
      config = described_class.new

      expect(config.validate!).to be(config)
    end

    it 'validates context file and runtime context shapes' do
      invalid = described_class.new(
        context_files: ['GLOSSARY.md', ''],
        supplemental_context: { '' => 'value', 'Valid name' => 123 }
      )

      expect { invalid.validate! }
        .to raise_error(
          I18nContextGenerator::Error,
          /context_files must be an array of non-empty strings.*supplemental_context must map non-empty string names to non-empty string values/
        )
    end

    it 'validates configured context file paths' do
      config = described_class.new(context_files: ['/missing/GLOSSARY.md'])

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, %r{context file not found: /missing/GLOSSARY\.md})
    end

    it 'serializes context file paths without runtime context contents' do
      config = described_class.new(
        context_files: %w[GLOSSARY.md localization-style.md],
        supplemental_context: { 'Pull request description' => 'Secret feature details' }
      )

      serialized = config.to_h

      expect(serialized.dig('context', 'files')).to eq(%w[GLOSSARY.md localization-style.md])
      expect(serialized.to_s).not_to include('Secret feature details', 'Pull request description')
    end

    it 'rejects unsafe numeric values' do
      config = described_class.new(
        concurrency: 0,
        context_lines: -1,
        max_matches_per_key: 1.5,
        max_prompt_chars: 1_999
      )

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /concurrency.*context_lines.*max_matches_per_key.*max_prompt_chars/)
    end

    it 'rejects unknown domain values loaded outside Thor' do
      config = described_class.new(
        provider: 'unknown',
        output_format: 'xml',
        context_mode: 'merge',
        discovery_mode: 'magic'
      )

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /provider.*output_format.*context_mode.*discovery_mode/)
    end

    it 'rejects malformed collection and scalar types' do
      config = described_class.new(
        translations: 'Localizable.strings',
        source_paths: [],
        ignore_patterns: 'build',
        swift_functions: 'MyLocalizedString',
        dry_run: 'yes',
        model: 123,
        context_prefix: nil
      )

      expect { config.validate! }
        .to raise_error(
          I18nContextGenerator::Error,
          /translations.*source_paths.*ignore_patterns.*swift_functions.*dry_run.*model/
        )
    end

    it 'rejects blank optional strings' do
      config = described_class.new(output_path: ' ', diff_base: '', diff_head: '')

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /output_path must be a non-empty string.*diff_base.*diff_head/)
    end

    it 'rejects missing translation and source paths' do
      config = described_class.new(
        translations: ['/missing/Localizable.strings'],
        source_paths: ['/missing/Sources']
      )

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /translation file not found.*source path not found/)
    end

    it 'infers output format and rejects explicit extension mismatches' do
      expect(described_class.new(output_path: 'context.json').validate!.output_format).to eq('json')

      config = described_class.new(output_path: 'context.json', output_format: 'csv')
      expect { config.validate! }.to raise_error(I18nContextGenerator::Error, /does not match .json path/)
    end

    it 'accepts structured stdout and rejects simultaneous file and stdout destinations' do
      stdout_config = described_class.new(output_stdout: true, output_format: 'json')

      expect(stdout_config.validate!).to be(stdout_config)
      expect(stdout_config.output_path).to eq('-')

      conventional_stdout = described_class.new(output_path: '-', output_format: 'json')
      expect(conventional_stdout.validate!).to be(conventional_stdout)
      expect(conventional_stdout.output_stdout).to be(true)

      conflict = described_class.new(output_path: 'context.json', output_stdout: true)
      expect { conflict.validate! }
        .to raise_error(I18nContextGenerator::Error, /output\.path and output\.stdout/)
    end

    it 'requires mutation destinations for preview-diff workflows' do
      valid = described_class.new(workflow_stage: 'preview_diff', write_back_to_code: true)
      expect(valid.validate!).to be(valid)

      missing = described_class.new(workflow_stage: 'preview_diff')
      expect { missing.validate! }
        .to raise_error(I18nContextGenerator::Error, /preview_diff requires write_back or write_back_to_code/)

      stdout = described_class.new(
        workflow_stage: 'preview_diff',
        write_back_to_code: true,
        output_stdout: true
      )
      expect { stdout.validate! }
        .to raise_error(I18nContextGenerator::Error, /preview_diff cannot write structured output/)

      file_output = described_class.new(
        workflow_stage: 'preview_diff',
        write_back: true,
        output_path: 'context.json'
      )
      expect { file_output.validate! }
        .to raise_error(I18nContextGenerator::Error, /preview_diff cannot write structured output/)
    end

    it 'requires an explicit model and safe endpoint for OpenAI-compatible providers' do
      valid = described_class.new(
        provider: 'openai_compatible',
        model: 'local-model',
        endpoint: 'http://127.0.0.1:11434/v1/responses'
      )

      expect(valid.validate!).to be(valid)

      missing = described_class.new(provider: 'openai_compatible')
      expect { missing.validate! }
        .to raise_error(
          I18nContextGenerator::Error,
          /requires an explicit model.*requires llm\.endpoint/
        )

      unsafe = described_class.new(
        provider: 'openai_compatible',
        model: 'remote-model',
        endpoint: 'http://llm.example.test/v1/responses'
      )
      expect { unsafe.validate! }
        .to raise_error(I18nContextGenerator::Error, /plain HTTP.*loopback/)

      [
        'http://[::1]:11434/v1/responses',
        'http://LOCALHOST:11434/v1/responses'
      ].each do |endpoint|
        loopback = described_class.new(
          provider: 'openai_compatible',
          model: 'local-model',
          endpoint: endpoint
        )
        expect(loopback.validate!).to be(loopback)
      end
    end

    it 'rejects provider endpoints on built-in remote providers' do
      config = described_class.new(
        provider: 'openai',
        endpoint: 'https://llm.example.test/v1/responses'
      )

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /supported only with the openai_compatible provider/)
    end

    it 'rejects missing output directories and unsupported output extensions' do
      config = described_class.new(output_path: '/missing/context.txt')

      expect { config.validate! }
        .to raise_error(I18nContextGenerator::Error, /extension must be .csv or .json.*output directory not found/)
    end

    it 'rejects a directory used as the output file' do
      Dir.mktmpdir do |dir|
        output_directory = File.join(dir, 'context.csv')
        FileUtils.mkdir_p(output_directory)

        expect { described_class.new(output_path: output_directory).validate! }
          .to raise_error(I18nContextGenerator::Error, /output path is a directory/)
      end
    end

    it 'rejects a file used as an enabled cache directory' do
      Dir.mktmpdir do |dir|
        cache_path = File.join(dir, 'cache-file')
        File.write(cache_path, 'not a directory')

        expect { described_class.new(no_cache: false, cache_dir: cache_path).validate! }
          .to raise_error(I18nContextGenerator::Error, /cache directory path is not a directory/)
      end
    end

    it 'rejects unsupported translation diff formats but allows source-mode hydration' do
      Dir.mktmpdir do |dir|
        json_path = File.join(dir, 'translations.json')
        File.write(json_path, '{}')

        translation_config = described_class.new(translations: [json_path], diff_base: 'main')
        expect { translation_config.validate! }
          .to raise_error(I18nContextGenerator::Error, /diff_base is not supported/)

        source_config = described_class.new(
          translations: [json_path],
          source_paths: [dir],
          discovery_mode: 'source',
          diff_base: 'main'
        )
        expect { source_config.validate! }.not_to raise_error
      end
    end

    it 'rejects unsupported translation write-back formats' do
      Dir.mktmpdir do |dir|
        json_path = File.join(dir, 'translations.json')
        File.write(json_path, '{}')
        config = described_class.new(translations: [json_path], write_back: true)

        expect { config.validate! }.to raise_error(I18nContextGenerator::Error, /write_back is not supported/)
      end
    end

    it 'requires write-back inputs and limits locale roots to configured YAML files' do
      empty_write_back = described_class.new(translations: [], write_back: true)
      expect { empty_write_back.validate! }
        .to raise_error(I18nContextGenerator::Error, /write_back requires at least one translation file/)

      Dir.mktmpdir do |dir|
        json_path = File.join(dir, 'translations.json')
        yaml_path = File.join(dir, 'translations.yml')
        File.write(json_path, '{}')
        File.write(yaml_path, '{}')

        wrong_format = described_class.new(
          translations: [json_path],
          translation_locales: { json_path => 'en' }
        )
        expect { wrong_format.validate! }
          .to raise_error(I18nContextGenerator::Error, /translation locale is supported only for YAML files/)

        unconfigured = described_class.new(
          translations: [yaml_path],
          translation_locales: { File.join(dir, 'other.yml') => 'en' }
        )
        expect { unconfigured.validate! }
          .to raise_error(I18nContextGenerator::Error, /translation locale references an unconfigured file/)
      end
    end

    it 'deduplicates repeated and overlapping source paths' do
      Dir.mktmpdir do |dir|
        nested = File.join(dir, 'Sources')
        FileUtils.mkdir_p(nested)

        config = described_class.new(source_paths: [nested, dir, File.join(dir, '.')])

        expect(config.source_paths).to eq([dir])
      end
    end
  end

  describe 'versioned client configuration' do
    it 'accepts unversioned files as schema version 1 and prints resolved values' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'config.yml')
        File.write(path, "source:\n  paths:\n    - .\n")

        config = described_class.from_file(path)
        resolved = config.to_h

        expect(config.schema_version).to eq(1)
        expect(resolved['schema_version']).to eq(1)
        expect(resolved.dig('llm', 'provider')).to eq('anthropic')
        expect(resolved.dig('output', 'stdout')).to be(false)
      end
    end

    it 'warns and ignores unknown keys in unversioned compatibility mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'legacy.yml')
        File.write(path, "prompt: Legacy prompt\nprocessing:\n  concurency: 2\n")

        expect { described_class.from_file(path) }
          .to output(/unknown top-level keys: prompt.*unknown processing keys: concurency.*unversioned config/m).to_stderr
      end
    end

    it 'rejects unsupported versions and unknown keys' do
      Dir.mktmpdir do |dir|
        future = File.join(dir, 'future.yml')
        unknown = File.join(dir, 'unknown.yml')
        unknown_translation = File.join(dir, 'unknown-translation.yml')
        File.write(future, "schema_version: 2\n")
        File.write(unknown, "schema_version: 1\nprocessing:\n  concurency: 2\n")
        File.write(unknown_translation, "schema_version: 1\ntranslations:\n  - path: Localizable.strings\n    local: en\n")

        expect { described_class.from_file(future) }
          .to raise_error(I18nContextGenerator::Error, /unsupported schema_version 2/)
        expect { described_class.from_file(unknown) }
          .to raise_error(I18nContextGenerator::Error, /unknown processing keys: concurency/)
        expect { described_class.from_file(unknown_translation) }
          .to raise_error(I18nContextGenerator::Error, /unknown keys: local/)
      end
    end
  end

  describe '.merge_ignore_patterns' do
    it 'extends the defaults and removes duplicates' do
      patterns = described_class.merge_ignore_patterns(['**/build/**', '**/Generated/**'])

      expect(patterns).to include(*described_class.default_ignore_patterns)
      expect(patterns).to include('**/Generated/**')
      expect(patterns.count('**/build/**')).to eq(1)
    end
  end
end
