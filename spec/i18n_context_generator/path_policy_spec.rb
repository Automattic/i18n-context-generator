# frozen_string_literal: true

RSpec.describe I18nContextGenerator::PathPolicy do
  it 'matches ignored directories and paths relative to configured roots' do
    Dir.mktmpdir do |dir|
      policy = described_class.new(
        ignore_patterns: ['generated/**', '**/build/**'],
        roots: [dir]
      )

      expect(policy.ignored?(File.join(dir, 'generated', 'File.swift'))).to be(true)
      expect(policy.ignored?(File.join(dir, 'build'), directory: true)).to be(true)
      expect(policy.ignored?(File.join(dir, 'Sources', 'File.swift'))).to be(false)
    end
  end

  it 'prunes ignored directories and deduplicates overlapping roots' do
    Dir.mktmpdir do |dir|
      sources = File.join(dir, 'Sources')
      ignored = File.join(dir, 'build')
      FileUtils.mkdir_p(sources)
      FileUtils.mkdir_p(ignored)
      source_file = File.join(sources, 'Screen.swift')
      File.write(source_file, 'Text("title")')
      File.write(File.join(ignored, 'Generated.swift'), 'Text("generated")')
      policy = described_class.new(ignore_patterns: ['**/build/**'], roots: [sources, dir])

      expect(policy.files([sources, dir]) { |file| file.end_with?('.swift') }).to eq([source_file])
    end
  end
end
