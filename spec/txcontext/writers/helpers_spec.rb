# frozen_string_literal: true

RSpec.describe Txcontext::Writers::Helpers do
  let(:helper_host) do
    Class.new do
      include Txcontext::Writers::Helpers
    end.new
  end

  describe '#skip_description?' do
    it 'skips placeholder failure descriptions' do
      expect(helper_host.skip_description?('No usage found in source code')).to be true
      expect(helper_host.skip_description?('Processing failed: timeout')).to be true
    end

    it 'keeps normal descriptions' do
      expect(helper_host.skip_description?('Primary action button on the settings screen')).to be false
    end
  end

  describe '#writable_result?' do
    it 'rejects errored results' do
      result = Txcontext::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'API error',
        error: 'timeout'
      )

      expect(helper_host.writable_result?(result)).to be false
    end

    it 'accepts valid results' do
      result = Txcontext::ContextExtractor::ExtractionResult.new(
        key: 'settings.title',
        text: 'Settings',
        description: 'Navigation title for settings'
      )

      expect(helper_host.writable_result?(result)).to be true
    end
  end

  describe '#find_swift_files' do
    it 'returns a single Swift file when given a file path' do
      Dir.mktmpdir do |dir|
        swift_file = File.join(dir, 'Feature.swift')
        File.write(swift_file, 'struct Feature {}')

        expect(helper_host.find_swift_files(swift_file)).to eq([swift_file])
      end
    end

    it 'recursively finds Swift files in a directory' do
      Dir.mktmpdir do |dir|
        top_level = File.join(dir, 'TopLevel.swift')
        nested_dir = File.join(dir, 'Sources', 'Nested')
        nested_swift = File.join(nested_dir, 'Nested.swift')
        non_swift = File.join(dir, 'Readme.md')

        FileUtils.mkdir_p(nested_dir)
        File.write(top_level, 'struct TopLevel {}')
        File.write(nested_swift, 'struct Nested {}')
        File.write(non_swift, '# docs')

        expect(helper_host.find_swift_files(dir)).to contain_exactly(top_level, nested_swift)
      end
    end

    it 'returns an empty array for missing paths or non-Swift files' do
      Dir.mktmpdir do |dir|
        text_file = File.join(dir, 'notes.txt')
        File.write(text_file, 'not swift')

        expect(helper_host.find_swift_files(File.join(dir, 'missing'))).to eq([])
        expect(helper_host.find_swift_files(text_file)).to eq([])
      end
    end

    it 'applies ignore patterns' do
      Dir.mktmpdir do |dir|
        included_dir = File.join(dir, 'App')
        ignored_dir = File.join(dir, 'Pods')
        included_file = File.join(included_dir, 'Feature.swift')
        ignored_file = File.join(ignored_dir, 'Vendor.swift')

        FileUtils.mkdir_p(included_dir)
        FileUtils.mkdir_p(ignored_dir)
        File.write(included_file, 'struct Feature {}')
        File.write(ignored_file, 'struct Vendor {}')

        expect(helper_host.find_swift_files(dir, ignore_patterns: ['**/Pods/**'])).to eq([included_file])
      end
    end
  end
end
