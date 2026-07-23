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

  it 'preserves all untouched Xcode formatting and skips empty placeholder keys' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      original = <<~JSON
        {
          "sourceLanguage" : "en",
          "strings" : {
            "" : {},
            "settings.title" : {
              "comment" : "Old context",
              "localizations" : {
                "fr" : {
                  "stringUnit" : {
                    "state" : "translated",
                    "value" : "Réglages"
                  }
                }
              }
            },
            "other" : {
              "comment" : "Keep me"
            }
          },
          "version" : "1.0"
        }
      JSON
      File.write(path, original)

      described_class.new.write(
        [build_result('settings.title', 'Title above the settings list')],
        path
      )

      expected = original.sub(
        '"comment" : "Old context"',
        '"comment" : "Context: Title above the settings list"'
      )
      expect(File.read(path)).to eq(expected)
    end
  end

  it 'does not rewrite the catalog when no result is writable' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      original = <<~JSON
        {
          "sourceLanguage" : "en",
          "strings" : {
            "settings.title" : {}
          },
          "version" : "1.0"
        }
      JSON
      File.write(path, original)
      result = build_result('settings.title', 'No usage found in source code')

      expect(described_class.new.write([result], path)).to be(false)
      expect(File.read(path)).to eq(original)
    end
  end

  it 'adds a comment to an empty catalog entry without reformatting the catalog' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      original = <<~JSON
        {
          "sourceLanguage" : "en",
          "strings" : {
            "settings.title" : {},
            "other" : {}
          },
          "version" : "1.0"
        }
      JSON
      File.write(path, original)

      described_class.new.write(
        [build_result('settings.title', 'Settings title')],
        path
      )

      expect(File.read(path)).to eq(
        original.sub(
          '"settings.title" : {}',
          "\"settings.title\" : {\n      \"comment\" : \"Context: Settings title\"\n    }"
        )
      )
      expect(Oj.load_file(path).dig('strings', 'settings.title', 'comment'))
        .to eq('Context: Settings title')
    end
  end

  it 'adds a comment to an inline compact catalog entry' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      original = '{"sourceLanguage":"en","strings":{"target":{}},"version":"1.0"}'
      File.write(path, original)

      described_class.new.write(
        [build_result('target', 'Compact context')],
        path
      )

      expect(File.read(path)).to eq(
        '{"sourceLanguage":"en","strings":{"target":{"comment":"Context: Compact context"}},"version":"1.0"}'
      )
      expect(Oj.load_file(path).dig('strings', 'target', 'comment'))
        .to eq('Context: Compact context')
    end
  end

  it 'infers block indentation from a non-inline sibling in mixed layouts' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage" : "en",
          "strings" : { "a.key" : {},
            "b.key" : { "extractionState" : "manual" }
          },
          "version" : "1.0"
        }
      JSON

      described_class.new.write(
        [
          build_result('a.key', 'First context'),
          build_result('b.key', 'Second context')
        ],
        path
      )
      catalog = Oj.load_file(path)

      expect(catalog.dig('strings', 'a.key', 'comment')).to eq('Context: First context')
      expect(catalog.dig('strings', 'b.key', 'comment')).to eq('Context: Second context')
      expect(catalog.dig('strings', 'b.key', 'extractionState')).to eq('manual')
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
