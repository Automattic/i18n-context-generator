# frozen_string_literal: true

require 'timeout'

RSpec.describe I18nContextGenerator::XcstringsDocument do
  it 'preserves Unicode content while editing and indexing by byte offset' do
    content = <<~JSON
      {
        "sourceLanguage" : "en",
        "strings" : {
          "préférences.🔒" : {
            "comment" : "Résumé conservé"
          },
          "settings.title" : {
            "comment" : "Old context"
          }
        },
        "version" : "1.0"
      }
    JSON
    document = described_class.new(content, path: 'Localizable.xcstrings')
    target_line = content.lines.index { |line| line.include?('"settings.title"') } + 1

    rendered = document.with_comments('settings.title' => 'Contexte révisé 🔒')

    expect(document.line_index.fetch(target_line)).to eq('settings.title')
    expect(rendered.encoding).to eq(content.encoding)
    expect(rendered).to eq(content.sub('"Old context"', '"Contexte révisé 🔒"'))
    expect(JSON.parse(rendered).dig('strings', 'préférences.🔒', 'comment')).to eq('Résumé conservé')
  end

  it 'indexes a generated Unicode catalog within a bounded time' do
    entry_count = 1_000
    strings = entry_count.times.to_h do |index|
      [
        "entry.#{index}.é",
        {
          'comment' => "Résumé numéro #{index} 🔒",
          'localizations' => {
            'fr' => {
              'stringUnit' => {
                'state' => 'translated',
                'value' => "Réglage #{index}"
              }
            }
          }
        }
      ]
    end
    content = JSON.pretty_generate(
      'sourceLanguage' => 'en',
      'strings' => strings,
      'version' => '1.0'
    )
    line_index = nil

    expect do
      Timeout.timeout(5) do
        line_index = described_class.new(content, path: 'Generated.xcstrings').line_index
      end
    end.not_to raise_error
    expect(line_index.values.uniq.size).to eq(entry_count)
  end
end
