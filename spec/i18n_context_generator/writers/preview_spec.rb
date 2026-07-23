# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Writers::Preview do
  it 'returns a sanitized patch without modifying the original file' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'Localizable.strings')
      File.write(path, "\"title\" = \"Title\";\n")
      original = File.binread(path)

      patch = described_class.render(path) do |candidate_path|
        File.write(candidate_path, "/* Context: Screen title */\n\"title\" = \"Title\";\n")
      end

      expect(patch).to include(
        "diff --git a/#{path} b/#{path}",
        "--- a/#{path}",
        "+++ b/#{path}",
        '+/* Context: Screen title */'
      )
      expect(patch).not_to include('i18n-context-preview-')
      expect(File.binread(path)).to eq(original)
    end
  end

  it 'returns nil when the candidate is unchanged' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'App.swift')
      File.write(path, "let title = \"Title\"\n")

      expect(described_class.render(path) { |candidate_path| FileUtils.touch(candidate_path) }).to be_nil
    end
  end
end
