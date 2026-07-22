# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Parsers::JsonParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'flattens nested keys and skips nil or blank values' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.json')
        File.write(path, <<~JSON)
          {
            "auth": {
              "title": "Sign in",
              "subtitle": "   "
            },
            "actions": ["Save", "Cancel"],
            "count": 3,
            "missing": null
          }
        JSON

        entries = parser.parse(path)

        expect(entries.map(&:key)).to contain_exactly('auth.title', 'actions', 'count')

        title = entries.find { |entry| entry.key == 'auth.title' }
        actions = entries.find { |entry| entry.key == 'actions' }
        count = entries.find { |entry| entry.key == 'count' }

        expect(title.text).to eq('Sign in')
        expect(actions.text).to eq('Save | Cancel')
        expect(count.text).to eq('3')
        expect(entries).to all(have_attributes(source_file: path))
      end
    end

    it 'preserves nested prefixes for deep hashes' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'deep.json')
        File.write(path, '{"profile":{"menu":{"title":"Profile"}}}')

        entries = parser.parse(path)

        expect(entries.map(&:key)).to eq(['profile.menu.title'])
        expect(entries.first.text).to eq('Profile')
      end
    end

    it 'wraps malformed JSON and rejects non-object roots' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.json')
        File.write(path, '{"broken":')

        expect { parser.parse(path) }
          .to raise_error(I18nContextGenerator::Error, /Failed to parse JSON translation file.*translations\.json/)

        File.write(path, '["not", "an", "object"]')
        expect { parser.parse(path) }
          .to raise_error(I18nContextGenerator::Error, /root must be an object/)
      end
    end
  end
end
