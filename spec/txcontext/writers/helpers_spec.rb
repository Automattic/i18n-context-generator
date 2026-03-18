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
  end
end
