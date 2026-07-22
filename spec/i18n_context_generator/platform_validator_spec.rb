# frozen_string_literal: true

RSpec.describe I18nContextGenerator::PlatformValidator do
  it 'rejects mixed iOS and Android source paths' do
    config = I18nContextGenerator::Config.new(
      translations: [File.join(ios_fixtures_path, 'Localizable.strings')],
      source_paths: [ios_fixtures_path, android_fixtures_path]
    )

    expect { described_class.new(config).validate! }
      .to raise_error(I18nContextGenerator::Error, /Mixed iOS and Android runs are not supported/)
  end

  it 'rejects mixed iOS and Android translation files' do
    config = I18nContextGenerator::Config.new(
      translations: [
        File.join(ios_fixtures_path, 'Localizable.strings'),
        File.join(android_fixtures_path, 'res', 'values', 'strings.xml')
      ],
      source_paths: [ios_fixtures_path]
    )

    expect { described_class.new(config).validate! }
      .to raise_error(I18nContextGenerator::Error, /Mixed iOS and Android runs are not supported/)
  end

  it 'allows a single platform after applying ignore patterns' do
    config = I18nContextGenerator::Config.new(
      translations: [File.join(ios_fixtures_path, 'Localizable.strings')],
      source_paths: [fixtures_path],
      ignore_patterns: ['**/android/**']
    )

    expect { described_class.new(config).validate! }.not_to raise_error
  end

  it 'returns the resolved platform and honors a compatible explicit override' do
    config = I18nContextGenerator::Config.new(
      translations: [],
      source_paths: [ios_fixtures_path],
      platform: 'ios'
    )

    expect(described_class.new(config).validate!).to eq(:ios)
  end

  it 'rejects an explicit platform that conflicts with detected inputs' do
    config = I18nContextGenerator::Config.new(
      translations: [],
      source_paths: [android_fixtures_path],
      platform: 'ios'
    )

    expect { described_class.new(config).validate! }
      .to raise_error(I18nContextGenerator::Error, /Configured platform ios conflicts with detected android/)
  end

  it 'does not treat headers as iOS evidence' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'Bridge.h'), '#define APP_NAME "Example"')
      File.write(File.join(dir, 'Screen.kt'), 'val title = R.string.title')
      config = I18nContextGenerator::Config.new(translations: [], source_paths: [dir])

      expect(described_class.new(config).validate!).to eq(:android)
    end
  end

  it 'rejects code write-back outside iOS Swift projects' do
    config = I18nContextGenerator::Config.new(
      translations: [],
      source_paths: [android_fixtures_path],
      write_back_to_code: true
    )

    expect { described_class.new(config).validate! }
      .to raise_error(I18nContextGenerator::Error, /write_back_to_code is supported only for iOS Swift sources/)
  end

  it 'requires a non-ignored Swift file for code write-back' do
    Dir.mktmpdir do |dir|
      generated_dir = File.join(dir, 'Generated')
      FileUtils.mkdir_p(generated_dir)
      File.write(File.join(generated_dir, 'Generated.swift'), 'Text("generated")')
      config = I18nContextGenerator::Config.new(
        translations: [],
        source_paths: [dir],
        ignore_patterns: ['**/Generated/**'],
        platform: 'ios',
        write_back_to_code: true
      )

      expect { described_class.new(config).validate! }
        .to raise_error(I18nContextGenerator::Error, /requires at least one non-ignored Swift source file/)
    end
  end
end
