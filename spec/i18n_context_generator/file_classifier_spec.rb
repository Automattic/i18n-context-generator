# frozen_string_literal: true

RSpec.describe I18nContextGenerator::FileClassifier do
  it 'distinguishes platform evidence from searchable headers' do
    expect(described_class.source_platform('Sources/Bridge.h')).to be_nil
    expect(described_class.searchable_platform('Sources/Bridge.h')).to eq(:ios)
    expect(described_class.source_platform('Sources/Screen.swift')).to eq(:ios)
    expect(described_class.source_platform('Sources/Screen.kt')).to eq(:android)
  end

  it 'classifies relative Android resource and values paths by component' do
    expect(described_class.android_resource_xml?('res/layout/screen.xml')).to be(true)
    expect(described_class.android_translation_file?('res/values-fr/messages.xml')).to be(true)
    expect(described_class.translation_platform('res/values/strings.xml')).to eq(:android)
    expect(described_class.android_resource_xml?('resources/layout/screen.xml')).to be(false)
  end

  it 'classifies Android manifests and searches them for Android or unknown runs' do
    manifest = 'app/src/main/AndroidManifest.xml'

    expect(described_class.searchable_source?(manifest, platform: :android)).to be(true)
    expect(described_class.searchable_platform(manifest, platform_hint: :android)).to eq(:android)
    expect(described_class.source_platform(manifest)).to eq(:android)
    expect(described_class.searchable_source?(manifest, platform: :unknown)).to be(true)
  end
end
