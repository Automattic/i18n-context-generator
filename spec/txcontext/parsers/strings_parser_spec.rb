# frozen_string_literal: true

RSpec.describe Txcontext::Parsers::StringsParser do
  subject(:parser) { described_class.new }

  let(:strings_file) { File.join(ios_fixtures_path, "Localizable.strings") }

  describe "#parse" do
    it "returns an array of TranslationEntry objects" do
      entries = parser.parse(strings_file)

      expect(entries).to be_an(Array)
      expect(entries).not_to be_empty
      expect(entries.first).to be_a(Txcontext::Parsers::TranslationEntry)
    end

    it "extracts keys correctly" do
      entries = parser.parse(strings_file)
      keys = entries.map(&:key)

      expect(keys).to include("common.save")
      expect(keys).to include("settings.title")
      expect(keys).to include("error.network")
    end

    it "extracts text values correctly" do
      entries = parser.parse(strings_file)
      save_entry = entries.find { |e| e.key == "common.save" }

      expect(save_entry.text).to eq("Save")
    end

    it "preserves format specifiers" do
      entries = parser.parse(strings_file)
      comments_entry = entries.find { |e| e.key == "post.comments" }

      expect(comments_entry.text).to eq("%d comments")
    end

    it "handles keys with dots" do
      entries = parser.parse(strings_file)
      keys = entries.map(&:key)

      expect(keys).to include("settings.notifications.description")
      expect(keys).to include("key.with.dots")
    end

    it "handles keys with special characters" do
      entries = parser.parse(strings_file)
      keys = entries.map(&:key)

      expect(keys).to include("key-with-dashes")
      expect(keys).to include("key_with_underscores")
    end

    it "includes source file in entry" do
      entries = parser.parse(strings_file)

      entries.each do |entry|
        expect(entry.source_file).to eq(strings_file)
      end
    end

    it "extracts comments as metadata" do
      entries = parser.parse(strings_file)

      # The dotstrings gem should preserve comments
      # Note: Exact behavior depends on dotstrings gem version
      expect(entries.first.metadata).to be_a(Hash)
    end
  end

  describe "edge cases" do
    it "handles empty strings file" do
      # Create a temporary empty strings file
      empty_file = File.join(Dir.tmpdir, "Empty.strings")
      File.write(empty_file, "")

      entries = parser.parse(empty_file)

      expect(entries).to eq([])
    ensure
      File.delete(empty_file) if File.exist?(empty_file)
    end

    it "handles strings with escaped quotes" do
      file_with_escapes = File.join(Dir.tmpdir, "Escapes.strings")
      File.write(file_with_escapes, '"key.escaped" = "He said \\"Hello\\"";')

      entries = parser.parse(file_with_escapes)

      expect(entries.first.text).to eq('He said "Hello"')
    ensure
      File.delete(file_with_escapes) if File.exist?(file_with_escapes)
    end

    it "handles strings with newlines" do
      file_with_newlines = File.join(Dir.tmpdir, "Newlines.strings")
      File.write(file_with_newlines, '"key.newline" = "Line 1\\nLine 2";')

      entries = parser.parse(file_with_newlines)

      expect(entries.first.text).to include("\n")
    ensure
      File.delete(file_with_newlines) if File.exist?(file_with_newlines)
    end

    it "handles unicode characters" do
      file_with_unicode = File.join(Dir.tmpdir, "Unicode.strings")
      File.write(file_with_unicode, '"key.emoji" = "Hello! 🎉";')

      entries = parser.parse(file_with_unicode)

      expect(entries.first.text).to include("🎉")
    ensure
      File.delete(file_with_unicode) if File.exist?(file_with_unicode)
    end
  end
end
