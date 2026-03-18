# frozen_string_literal: true

RSpec.describe Txcontext::Parsers::YamlParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'strips a top-level locale key and skips nil or blank values' do
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

        entries = parser.parse(path)

        expect(entries.map(&:key)).to contain_exactly('auth.title', 'actions')

        title = entries.find { |entry| entry.key == 'auth.title' }
        actions = entries.find { |entry| entry.key == 'actions' }

        expect(title.text).to eq('Entrar')
        expect(actions.text).to eq('Salvar | Cancelar')
        expect(entries).to all(have_attributes(source_file: path))
      end
    end

    it 'preserves non-locale top-level namespaces' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'errors.yml')
        File.write(path, <<~YAML)
          errors:
            network: Offline
        YAML

        entries = parser.parse(path)

        expect(entries.map(&:key)).to eq(['errors.network'])
        expect(entries.first.text).to eq('Offline')
      end
    end
  end
end
