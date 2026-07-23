# frozen_string_literal: true

RSpec.describe I18nContextGenerator::AndroidResource do
  describe 'identity normalization' do
    it 'normalizes strings, plurals, and arrays' do
      expect(described_class.base_key('title')).to eq('title')
      expect(described_class.base_key('items:other')).to eq('items')
      expect(described_class.base_key('weekdays[12]')).to eq('weekdays')
      expect(described_class.type_for('items:other')).to eq(:plural)
      expect(described_class.type_for('weekdays[12]')).to eq(:array)
      expect(described_class.composite_key('items', type: :plural, quantity: 'one')).to eq('items:one')
    end
  end

  describe '.index' do
    it 'indexes multiline resources and exact collection members' do
      content = <<~XML
        <resources>
          <string name="title">
            Title
          </string>
          <string-array name="weekdays">
            <item>Monday</item>
            <item>
              Tuesday
            </item>
          </string-array>
        </resources>
      XML

      index = described_class.index(content)

      expect(index.span_for('title').line_span).to eq(2..4)
      expect(index.span_for('weekdays[1]').line_span).to eq(7..9)
      expect(index.span_for('weekdays[1]').parent_line_span).to eq(5..10)
      expect(index.base_key_at(8)).to eq('weekdays')
      expect(index.member_at(8, parent: 'weekdays')).to eq('weekdays[1]')
    end

    it 'returns no exact member when multiple items share a line' do
      content = '<resources><string-array name="values"><item>A</item><item>B</item></string-array></resources>'

      expect(described_class.index(content).member_at(1, parent: 'values')).to be_nil
    end

    it 'ignores resource-shaped examples inside comments' do
      content = <<~XML
        <resources>
          <!-- <string name="example">Not a resource</string> -->
          <string name="real">Real</string>
        </resources>
      XML

      expect(described_class.index(content).entry_spans.map(&:key)).to eq(['real'])
    end

    it 'ignores item-shaped text inside CDATA sections' do
      content = <<~XML
        <resources>
          <string-array name="examples">
            <item><![CDATA[Example: <item>not another entry</item>]]></item>
            <item>Real second entry</item>
          </string-array>
        </resources>
      XML

      expect(described_class.index(content).entry_spans.map(&:key)).to eq(%w[examples[0] examples[1]])
    end
  end
end
