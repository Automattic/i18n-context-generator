# frozen_string_literal: true

require 'tempfile'

RSpec.describe Txcontext::Writers::JsonWriter do
  describe '#write' do
    let(:writer) { described_class.new }

    it 'writes JSON output with an ISO8601 timestamp' do
      result = Txcontext::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Navigation title for the settings screen',
        ui_element: 'title',
        tone: 'neutral',
        max_length: 20,
        locations: ['SettingsViewController.swift:42']
      )

      Tempfile.create(['txcontext', '.json']) do |file|
        writer.write([result], file.path)
        output = Oj.load_file(file.path)

        expect(output['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T/)
        expect(output['version']).to eq(Txcontext::VERSION)
        expect(output['total']).to eq(1)
        expect(output['entries'].first['key']).to eq('settings.title')
        expect(output['entries'].first.dig('context', 'ui_element')).to eq('title')
      end
    end
  end
end
