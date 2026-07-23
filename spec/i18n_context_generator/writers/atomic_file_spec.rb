# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Writers::AtomicFile do
  describe '.replace' do
    it 'atomically replaces content and preserves file permissions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, 'original')
        File.chmod(0o640, path)

        described_class.replace(path, 'updated') do |candidate_path|
          expect(File.dirname(candidate_path)).to eq(dir)
          expect(File.read(candidate_path)).to eq('updated')
        end

        expect(File.read(path)).to eq('updated')
        expect(File.stat(path).mode & 0o777).to eq(0o640)
        expect(Dir.children(dir)).to eq(['Localizable.strings'])
      end
    end

    it 'leaves the original unchanged and removes the candidate when validation fails' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        original = '<resources><string name="title">Title</string></resources>'
        File.write(path, original)

        expect do
          described_class.replace(path, '<invalid>') do
            raise REXML::ParseException, 'invalid candidate'
          end
        end.to raise_error(REXML::ParseException, 'invalid candidate')

        expect(File.read(path)).to eq(original)
        expect(Dir.children(dir)).to eq(['strings.xml'])
      end
    end
  end
end
