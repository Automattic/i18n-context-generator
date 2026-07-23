# frozen_string_literal: true

RSpec.describe I18nContextGenerator::SupplementalContext do
  describe '.load' do
    it 'loads complete files and named runtime values in stable order' do
      Dir.mktmpdir do |dir|
        glossary = File.join(dir, 'GLOSSARY.md')
        style = File.join(dir, 'localization-style.md')
        File.write(glossary, "# Reader\nA product surface.\n")
        File.write(style, "Use sentence case.\n")

        sources = described_class.load(
          files: [glossary, style],
          runtime: {
            'Pull request title' => 'Improve Reader labels',
            'Pull request description' => 'Clarifies subscription status.'
          }
        )

        expect(sources.map { |source| [source.kind, source.name, source.content] }).to eq(
          [
            [:file, 'GLOSSARY.md', "# Reader\nA product surface.\n"],
            [:file, 'localization-style.md', "Use sentence case.\n"],
            [:runtime, 'Pull request title', 'Improve Reader labels'],
            [:runtime, 'Pull request description', 'Clarifies subscription status.']
          ]
        )
        expect(sources).to be_frozen
        expect(sources).to all(be_frozen)
        expect(sources.flat_map { |source| [source.name, source.content] }).to all(be_frozen)
      end
    end

    it 'reads each configured file once per load' do
      Dir.mktmpdir do |dir|
        glossary = File.join(dir, 'GLOSSARY.md')
        File.write(glossary, 'Product terminology')
        allow(File).to receive(:binread).and_call_original

        described_class.load(files: [glossary], runtime: {})

        expect(File).to have_received(:binread).with(glossary).once
      end
    end

    it 'scrubs invalid UTF-8 while preserving otherwise free-form content' do
      Dir.mktmpdir do |dir|
        glossary = File.join(dir, 'GLOSSARY.md')
        File.binwrite(glossary, "Reader\xFF terminology")

        source = described_class.load(files: [glossary], runtime: {}).first

        expect(source.content).to eq("Reader\uFFFD terminology")
        expect(source.content.encoding).to eq(Encoding::UTF_8)
      end
    end

    it 'rejects empty and binary context files with the path in the error' do
      Dir.mktmpdir do |dir|
        empty = File.join(dir, 'empty.md')
        binary = File.join(dir, 'binary.md')
        File.write(empty, " \n")
        File.binwrite(binary, "Reader\0terminology")

        expect { described_class.load(files: [empty], runtime: {}) }
          .to raise_error(I18nContextGenerator::Error, /context file is empty: #{Regexp.escape(empty)}/)
        expect { described_class.load(files: [binary], runtime: {}) }
          .to raise_error(I18nContextGenerator::Error, /context file is not text: #{Regexp.escape(binary)}/)
      end
    end

    it 'wraps file read failures with an actionable context error' do
      allow(File).to receive(:binread).with('GLOSSARY.md').and_raise(Errno::EACCES, 'permission denied')

      expect { described_class.load(files: ['GLOSSARY.md'], runtime: {}) }
        .to raise_error(I18nContextGenerator::Error, /Unable to read context file GLOSSARY\.md:.*permission denied/)
    end

    it 'rejects invalid runtime mappings even when called without Config validation' do
      expect { described_class.load(files: [], runtime: []) }
        .to raise_error(I18nContextGenerator::Error, /supplemental_context must be a mapping/)
      expect { described_class.load(files: [], runtime: { '' => 'value' }) }
        .to raise_error(I18nContextGenerator::Error, /context name must be a non-empty string/)
      expect { described_class.load(files: [], runtime: { 'PR title' => '' }) }
        .to raise_error(I18nContextGenerator::Error, /context value for PR title must be a non-empty string/)
    end
  end
end
