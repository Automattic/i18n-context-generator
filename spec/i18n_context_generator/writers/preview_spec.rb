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
        'diff --git a/Localizable.strings b/Localizable.strings',
        '--- a/Localizable.strings',
        '+++ b/Localizable.strings',
        '+/* Context: Screen title */'
      )
      expect(patch).not_to include('a//')
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

  it 'rewrites only file headers and preserves header-looking hunk lines' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'App.swift')
      File.write(path, "-- MARK: old\n")

      patch = described_class.render(path) do |candidate_path|
        File.write(candidate_path, "++ MARK: new\n")
      end

      expect(patch).to include(
        '--- a/App.swift',
        '+++ b/App.swift',
        '--- MARK: old',
        '+++ MARK: new'
      )
    end
  end

  it 'emits a patch accepted by git apply' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('App.swift', "let title = \"Old\"\n")
        patch = described_class.render('App.swift') do |candidate_path|
          File.write(candidate_path, "let title = \"New\"\n")
        end

        _stdout, stderr, status = Open3.capture3('git', 'apply', '--check', '-', stdin_data: patch)

        expect(status).to be_success, stderr
      end
    end
  end
end
