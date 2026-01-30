# frozen_string_literal: true

RSpec.describe Txcontext::Parsers::AndroidXmlParser do
  subject(:parser) { described_class.new }

  let(:strings_xml) { File.join(android_fixtures_path, "res", "values", "strings.xml") }

  describe "#parse" do
    it "returns an array of TranslationEntry objects" do
      entries = parser.parse(strings_xml)

      expect(entries).to be_an(Array)
      expect(entries).not_to be_empty
      expect(entries.first).to be_a(Txcontext::Parsers::TranslationEntry)
    end

    it "extracts string keys correctly" do
      entries = parser.parse(strings_xml)
      keys = entries.map(&:key)

      expect(keys).to include("app_name")
      expect(keys).to include("common_save")
      expect(keys).to include("settings_title")
    end

    it "extracts text values correctly" do
      entries = parser.parse(strings_xml)
      save_entry = entries.find { |e| e.key == "common_save" }

      expect(save_entry.text).to eq("Save")
    end

    it "unescapes Android string escapes" do
      entries = parser.parse(strings_xml)
      unauthorized = entries.find { |e| e.key == "error_unauthorized" }

      # Should unescape \' to '
      expect(unauthorized.text).to include("don't")
    end

    it "preserves format specifiers" do
      entries = parser.parse(strings_xml)
      comments = entries.find { |e| e.key == "post_comments" }

      expect(comments.text).to eq("%d comments")
    end

    it "handles positional format specifiers" do
      entries = parser.parse(strings_xml)
      format_example = entries.find { |e| e.key == "compose_format_example" }

      expect(format_example.text).to include("%1$d")
      expect(format_example.text).to include("%2$s")
    end

    it "includes source file in entry" do
      entries = parser.parse(strings_xml)

      entries.each do |entry|
        expect(entry.source_file).to eq(strings_xml)
      end
    end
  end

  describe "plurals parsing" do
    it "parses plural resources" do
      entries = parser.parse(strings_xml)
      plural_keys = entries.select { |e| e.key.start_with?("post_likes_count:") }

      expect(plural_keys).not_to be_empty
    end

    it "creates entries for each quantity" do
      entries = parser.parse(strings_xml)

      one_entry = entries.find { |e| e.key == "post_likes_count:one" }
      other_entry = entries.find { |e| e.key == "post_likes_count:other" }

      expect(one_entry).not_to be_nil
      expect(one_entry.text).to eq("%d like")
      expect(other_entry).not_to be_nil
      expect(other_entry.text).to eq("%d likes")
    end

    it "includes plural metadata" do
      entries = parser.parse(strings_xml)
      one_entry = entries.find { |e| e.key == "post_likes_count:one" }

      expect(one_entry.metadata[:plural]).to eq("post_likes_count")
      expect(one_entry.metadata[:quantity]).to eq("one")
    end
  end

  describe "edge cases" do
    it "handles empty strings.xml" do
      empty_file = File.join(Dir.tmpdir, "empty_strings.xml")
      File.write(empty_file, '<?xml version="1.0" encoding="utf-8"?><resources></resources>')

      entries = parser.parse(empty_file)

      expect(entries).to eq([])
    ensure
      File.delete(empty_file) if File.exist?(empty_file)
    end

    it "handles strings with XML entities" do
      file_with_entities = File.join(Dir.tmpdir, "entities_strings.xml")
      content = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="with_entities">Hello &amp; World &lt;test&gt;</string>
        </resources>
      XML
      File.write(file_with_entities, content)

      entries = parser.parse(file_with_entities)

      expect(entries.first.text).to eq("Hello & World <test>")
    ensure
      File.delete(file_with_entities) if File.exist?(file_with_entities)
    end

    it "handles empty string values" do
      file_with_empty = File.join(Dir.tmpdir, "empty_value_strings.xml")
      content = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="empty_value"></string>
        </resources>
      XML
      File.write(file_with_empty, content)

      entries = parser.parse(file_with_empty)

      expect(entries.first.text).to eq("")
    ensure
      File.delete(file_with_empty) if File.exist?(file_with_empty)
    end

    it "handles translatable=false attribute" do
      # Note: This depends on whether the parser filters these out
      # Currently it doesn't, but this documents the behavior
      file_with_translatable = File.join(Dir.tmpdir, "translatable_strings.xml")
      content = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string name="translatable_key">Translate me</string>
            <string name="not_translatable" translatable="false">Do not translate</string>
        </resources>
      XML
      File.write(file_with_translatable, content)

      entries = parser.parse(file_with_translatable)
      keys = entries.map(&:key)

      expect(keys).to include("translatable_key")
      # Current behavior: non-translatable strings are still parsed
      expect(keys).to include("not_translatable")
    ensure
      File.delete(file_with_translatable) if File.exist?(file_with_translatable)
    end
  end

  describe "string arrays" do
    it "parses string-array resources" do
      file_with_array = File.join(Dir.tmpdir, "array_strings.xml")
      content = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string-array name="days_of_week">
                <item>Monday</item>
                <item>Tuesday</item>
                <item>Wednesday</item>
            </string-array>
        </resources>
      XML
      File.write(file_with_array, content)

      entries = parser.parse(file_with_array)

      expect(entries.map(&:key)).to include("days_of_week[0]")
      expect(entries.map(&:key)).to include("days_of_week[1]")
      expect(entries.map(&:key)).to include("days_of_week[2]")

      monday = entries.find { |e| e.key == "days_of_week[0]" }
      expect(monday.text).to eq("Monday")
    ensure
      File.delete(file_with_array) if File.exist?(file_with_array)
    end

    it "includes array metadata" do
      file_with_array = File.join(Dir.tmpdir, "array_meta_strings.xml")
      content = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <resources>
            <string-array name="colors">
                <item>Red</item>
            </string-array>
        </resources>
      XML
      File.write(file_with_array, content)

      entries = parser.parse(file_with_array)
      entry = entries.first

      expect(entry.metadata[:array]).to eq("colors")
      expect(entry.metadata[:index]).to eq(0)
    ensure
      File.delete(file_with_array) if File.exist?(file_with_array)
    end
  end
end
