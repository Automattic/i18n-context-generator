# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Parsers::YamlParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'strips an explicitly configured locale key and skips nil or blank values' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')
        File.write(path, <<~YAML)
          pt-BR:
            auth:
              title: Entrar
              subtitle: "   "
            actions:
              - Salvar
              - Cancelar
            missing:
        YAML

        entries = described_class.new(locale: 'pt-BR').parse(path)

        expect(entries.map(&:key)).to contain_exactly('auth.title', 'actions')

        title = entries.find { |entry| entry.key == 'auth.title' }
        actions = entries.find { |entry| entry.key == 'actions' }

        expect(title.text).to eq('Entrar')
        expect(actions.text).to eq('Salvar | Cancelar')
        expect(entries).to all(have_attributes(source_file: path))
      end
    end

    it 'preserves top-level namespaces unless a locale is explicitly configured' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')

        %w[errors app to-do id-card es-419 zh-Hant-TW].each do |namespace|
          File.write(path, "#{namespace}:\n  title: Example\n")

          expect(parser.parse(path).map(&:key)).to eq(["#{namespace}.title"])
        end
      end
    end

    it 'supports an explicit locale root without guessing from the namespace' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')
        File.write(path, "application:\n  title: My app\n")

        entries = described_class.new(locale: 'application').parse(path)

        expect(entries.map(&:key)).to eq(['title'])
      end
    end

    it 'wraps malformed YAML and rejects non-mapping roots' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')
        File.write(path, "broken: [\n")

        expect { parser.parse(path) }
          .to raise_error(I18nContextGenerator::Error, /Failed to parse YAML translation file.*line/)

        File.write(path, "- not\n- a mapping\n")
        expect { parser.parse(path) }
          .to raise_error(I18nContextGenerator::Error, /root must be a mapping/)
      end
    end

    it 'wraps unsupported YAML aliases' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')
        File.write(path, "en: &translations\n  title: Settings\ncopy: *translations\n")

        expect { parser.parse(path) }
          .to raise_error(I18nContextGenerator::Error, /Failed to parse YAML translation file.*Alias parsing was not enabled/)
      end
    end

    it 'fails clearly when an explicit locale root is missing' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'translations.yml')
        File.write(path, "fr:\n  title: Réglages\n")

        expect { described_class.new(locale: 'en').parse(path) }
          .to raise_error(I18nContextGenerator::Error, /does not contain locale root "en"/)
      end
    end
  end
end
