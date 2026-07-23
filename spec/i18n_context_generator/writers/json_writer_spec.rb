# frozen_string_literal: true

require 'tempfile'

RSpec.describe I18nContextGenerator::Writers::JsonWriter do
  describe '#write' do
    let(:writer) { described_class.new }

    it 'writes JSON output with an ISO8601 timestamp' do
      result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Navigation title for the settings screen',
        ui_element: 'title',
        tone: 'neutral',
        max_length: 20,
        confidence: 'medium',
        ambiguity_reason: 'Only one usage was supplied',
        request_count: 1,
        input_tokens: 200,
        output_tokens: 40,
        retries: 1,
        locations: ['SettingsViewController.swift:42']
      )
      metrics = I18nContextGenerator::RunMetrics.from(
        [result],
        provider: 'openai',
        model: 'gpt-5-mini'
      )

      Tempfile.create(['i18n-context-generator', '.json']) do |file|
        writer.write([result], file.path, metrics: metrics)
        output = Oj.load_file(file.path)

        expect(output['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T/)
        expect(output['version']).to eq(I18nContextGenerator::VERSION)
        expect(output['total']).to eq(1)
        expect(output['entries'].first['key']).to eq('settings.title')
        expect(output['entries'].first.dig('context', 'ui_element')).to eq('title')
        expect(output['entries'].first.dig('context', 'confidence')).to eq('medium')
        expect(output['entries'].first.dig('telemetry', 'retries')).to eq(1)
        expect(output.dig('metrics', 'request_count')).to eq(1)
        expect(output.dig('metrics', 'estimated_cost_usd')).to eq(0.00013)
      end
    end

    it 'writes parseable JSON directly to stdout' do
      result = I18nContextGenerator::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Settings title'
      )

      expect { writer.write([result], '-') }
        .to output(/\A\{.*"settings.title".*\}\n\z/m).to_stdout
    end
  end
end
