# frozen_string_literal: true

RSpec.describe Txcontext::PlatformValidator do
  it 'rejects mixed iOS and Android source paths' do
    config = Txcontext::Config.new(
      translations: [File.join(ios_fixtures_path, 'Localizable.strings')],
      source_paths: [ios_fixtures_path, android_fixtures_path]
    )

    expect { described_class.new(config).validate! }
      .to raise_error(Txcontext::Error, /Mixed iOS and Android runs are not supported/)
  end

  it 'rejects mixed iOS and Android translation files' do
    config = Txcontext::Config.new(
      translations: [
        File.join(ios_fixtures_path, 'Localizable.strings'),
        File.join(android_fixtures_path, 'res', 'values', 'strings.xml')
      ],
      source_paths: [ios_fixtures_path]
    )

    expect { described_class.new(config).validate! }
      .to raise_error(Txcontext::Error, /Mixed iOS and Android runs are not supported/)
  end

  it 'allows a single platform after applying ignore patterns' do
    config = Txcontext::Config.new(
      translations: [File.join(ios_fixtures_path, 'Localizable.strings')],
      source_paths: [fixtures_path],
      ignore_patterns: ['**/android/**']
    )

    expect { described_class.new(config).validate! }.not_to raise_error
  end
end
