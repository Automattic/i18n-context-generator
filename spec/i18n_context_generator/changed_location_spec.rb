# frozen_string_literal: true

RSpec.describe I18nContextGenerator::ChangedLocation do
  it 'parses legacy location strings as right-side locations' do
    location = described_class.parse('Sources/Settings.swift:42')

    expect(location).to have_attributes(
      file: 'Sources/Settings.swift',
      line: 42,
      side: :right,
      fallback_line: nil
    )
    expect(location.to_s).to eq('Sources/Settings.swift:42')
  end

  it 'serializes side and fallback metadata' do
    location = described_class.new(
      file: 'Localizable.strings',
      line: 4,
      side: :left,
      fallback_line: 3
    )

    expect(location.to_h).to eq(
      file: 'Localizable.strings',
      line: 4,
      side: :left,
      fallback_line: 3
    )
    expect(location.review_side).to eq('LEFT')
  end
end
