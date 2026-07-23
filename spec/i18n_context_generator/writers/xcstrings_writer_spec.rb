# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Writers::XcstringsWriter do
  def build_result(key, description, source_file: nil)
    I18nContextGenerator::ContextExtractor::ExtractionResult.new(
      key: key,
      text: 'Settings',
      description: description,
      source_file: source_file
    )
  end

  it 'updates only the matching catalog comment and remains idempotent' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage": "en",
          "strings": {
            "settings.title": {
              "comment": "Old context",
              "localizations": {
                "fr": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Réglages"
                  }
                }
              }
            },
            "other": { "comment": "Keep me" }
          },
          "version": "1.0"
        }
      JSON
      writer = described_class.new
      results = [build_result('settings.title', 'Title above the settings list')]

      writer.write(results, path)
      first_output = File.read(path)
      writer.write(results, path)
      catalog = Oj.load_file(path)

      expect(catalog.dig('strings', 'settings.title', 'comment'))
        .to eq('Context: Title above the settings list')
      expect(catalog.dig('strings', 'settings.title', 'localizations', 'fr', 'stringUnit', 'value'))
        .to eq('Réglages')
      expect(catalog.dig('strings', 'other', 'comment')).to eq('Keep me')
      expect(File.read(path)).to eq(first_output)
    end
  end

  it 'appends generated context to a manual catalog comment' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage": "en",
          "strings": {
            "settings.title": { "comment": "Manual note" }
          },
          "version": "1.0"
        }
      JSON

      described_class.new(context_mode: 'append').write(
        [build_result('settings.title', 'Settings title')],
        path
      )

      expect(Oj.load_file(path).dig('strings', 'settings.title', 'comment'))
        .to eq("Manual note\nContext: Settings title")
    end
  end
end
