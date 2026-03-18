# frozen_string_literal: true

RSpec.describe Txcontext::Parsers::Base do
  describe '.for' do
    it 'selects the JSON parser for .json files' do
      expect(described_class.for('config/translations.json')).to be_a(Txcontext::Parsers::JsonParser)
    end

    it 'selects the YAML parser for .yml and .yaml files' do
      expect(described_class.for('config/translations.yml')).to be_a(Txcontext::Parsers::YamlParser)
      expect(described_class.for('config/translations.yaml')).to be_a(Txcontext::Parsers::YamlParser)
    end

    it 'selects the strings parser for .strings files' do
      expect(described_class.for('ios/Localizable.strings')).to be_a(Txcontext::Parsers::StringsParser)
    end

    it 'selects the Android XML parser for strings.xml files' do
      expect(described_class.for('android/res/values/strings.xml')).to be_a(Txcontext::Parsers::AndroidXmlParser)
    end

    it 'rejects unsupported XML files' do
      expect { described_class.for('android/res/layout/activity_main.xml') }
        .to raise_error(Txcontext::Error, /Unsupported XML format/)
    end

    it 'rejects unsupported file formats' do
      expect { described_class.for('translations.toml') }
        .to raise_error(Txcontext::Error, /Unsupported translation file format/)
    end
  end

  describe '#parse' do
    it 'raises unless a subclass implements it' do
      expect { described_class.new.parse('translations.json') }
        .to raise_error(NotImplementedError, /Subclasses must implement/)
    end
  end

  describe '#flatten_keys' do
    it 'flattens nested hashes and joins arrays' do
      flattened = described_class.new.send(
        :flatten_keys,
        {
          'auth' => {
            'title' => 'Sign in',
            'actions' => %w[Save Cancel]
          },
          'count' => 3,
          'empty' => nil
        }
      )

      expect(flattened).to eq(
        'auth.title' => 'Sign in',
        'auth.actions' => 'Save | Cancel',
        'count' => 3,
        'empty' => nil
      )
    end
  end
end
