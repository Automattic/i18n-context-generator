# frozen_string_literal: true

RSpec.describe Txcontext::Writers::CsvWriter do
  def build_result(key:, text:, description:, error: nil)
    Txcontext::ContextExtractor::ExtractionResult.new(
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
end
