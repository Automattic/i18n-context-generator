# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Parsers::XcstringsParser do
  subject(:parser) { described_class.new }

  it 'reads source-language values, catalog comments, and plural variants' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage": "en",
          "strings": {
            "settings.title": {
              "comment": "Title above the settings list",
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Settings"
                  }
                }
              }
            },
            "items.count": {
              "localizations": {
                "en": {
                  "variations": {
                    "plural": {
                      "one": { "stringUnit": { "state": "translated", "value": "%lld item" } },
                      "other": { "stringUnit": { "state": "translated", "value": "%lld items" } }
                    }
                  }
                }
              }
            },
            "Source text is the key": {}
          },
          "version": "1.0"
        }
      JSON

      entries = parser.parse(path)

      expect(entries).to include(
        have_attributes(
          key: 'settings.title',
          text: 'Settings',
          source_file: path,
          metadata: include(
            comment: 'Title above the settings list',
            source_language: 'en',
            resource_type: :string
          )
        ),
        have_attributes(key: 'items.count', text: '%lld item | %lld items'),
        have_attributes(key: 'Source text is the key', text: 'Source text is the key')
      )
    end
  end

  it 'skips entries explicitly marked as not translatable' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage": "en",
          "strings": {
            "visible": {},
            "hidden": { "shouldTranslate": false }
          },
          "version": "1.0"
        }
      JSON

      expect(parser.parse(path).map(&:key)).to eq(['visible'])
    end
  end

  it 'accepts valid empty placeholder keys and skips them' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.xcstrings')
      File.write(path, <<~JSON)
        {
          "sourceLanguage" : "en",
          "strings" : {
            "" : {},
            "visible" : {}
          },
          "version" : "1.0"
        }
      JSON

      expect(parser.parse(path).map(&:key)).to eq(['visible'])
    end
  end

  it 'wraps malformed catalogs in an actionable error' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Broken.xcstrings')
      File.write(path, '{"sourceLanguage":"en","strings":[]}')

      expect { parser.parse(path) }
        .to raise_error(I18nContextGenerator::Error, /Apple string catalog.*strings must be a mapping/)
    end
  end
end
