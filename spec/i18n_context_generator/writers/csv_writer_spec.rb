# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Writers::CsvWriter do
  def build_result(key:, text:, description:, error: nil)
    I18nContextGenerator::ContextExtractor::ExtractionResult.new(
      key: key,
      text: text,
      description: description,
      error: error
    )
  end

  it 'prefixes spreadsheet formula-looking cells to avoid CSV injection' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'context.csv')
      results = [
        build_result(
          key: '=SUM(A1:A2)',
          text: '+malicious',
          description: '-dangerous',
          error: '@oops'
        )
      ]

      described_class.new.write(results, path)

      output = File.read(path)
      expect(output).to include("'=SUM(A1:A2)")
      expect(output).to include("'+malicious")
      expect(output).to include("'-dangerous")
      expect(output).to include("'@oops")
    end
  end

  it 'leaves normal cells unchanged' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'context.csv')
      results = [build_result(key: 'settings.title', text: 'Settings', description: 'Navigation title')]

      described_class.new.write(results, path)

      output = File.read(path)
      expect(output).to include('settings.title')
      expect(output).to include('Settings')
      expect(output).not_to include("'settings.title")
    end
  end

  it 'writes parseable CSV directly to stdout' do
    result = build_result(
      key: 'settings.title',
      text: 'Settings',
      description: 'Navigation title'
    )

    expect { described_class.new.write([result], '-') }
      .to output(/\Aschema_version,key,source_file,translation_key.*settings\.title.*Settings,Navigation title/m).to_stdout
  end

  it 'writes source identity and typed diff locations' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'context.csv')
      result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        translation_key: 'settings.title',
        source_file: 'Localizable.strings',
        text: 'Settings',
        description: 'Navigation title',
        changed_translation_locations: [
          I18nContextGenerator::ChangedLocation.new(
            file: 'Localizable.strings',
            line: 2,
            side: :left,
            fallback_line: 1
          )
        ]
      )

      described_class.new.write([result], path)
      row = CSV.read(path, headers: true).first

      expect(row['schema_version']).to eq('1')
      expect(row['source_file']).to eq('Localizable.strings')
      expect(row['translation_key']).to eq('settings.title')
      expect(Oj.load(row['changed_translation_locations']).first).to include(
        'file' => 'Localizable.strings',
        'side' => 'left',
        'fallback_line' => 1
      )
    end
  end
end
