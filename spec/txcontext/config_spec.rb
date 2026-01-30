# frozen_string_literal: true

RSpec.describe Txcontext::Config do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new

      expect(config.translations).to eq([])
      expect(config.source_paths).to eq(["."])
      expect(config.ignore_patterns).to eq([])
      expect(config.provider).to eq("anthropic")
      expect(config.concurrency).to eq(5)
      expect(config.context_lines).to eq(20)
      expect(config.max_matches_per_key).to eq(3)
      expect(config.output_path).to be_nil
      expect(config.output_format).to eq("csv")
      expect(config.no_cache).to be true
      expect(config.dry_run).to be false
      expect(config.write_back).to be false
      expect(config.context_prefix).to eq("Context: ")
      expect(config.context_mode).to eq("replace")
    end

    it "accepts custom values" do
      config = described_class.new(
        translations: ["/path/to/file.strings"],
        source_paths: ["/path/to/sources"],
        concurrency: 10,
        output_path: "output.csv",
        no_cache: false,
        dry_run: true
      )

      expect(config.translations).to eq(["/path/to/file.strings"])
      expect(config.source_paths).to eq(["/path/to/sources"])
      expect(config.concurrency).to eq(10)
      expect(config.output_path).to eq("output.csv")
      expect(config.no_cache).to be false
      expect(config.dry_run).to be true
    end

    it "allows empty context_prefix" do
      config = described_class.new(context_prefix: "")

      expect(config.context_prefix).to eq("")
    end

    it "allows nil output_path" do
      config = described_class.new(output_path: nil)

      expect(config.output_path).to be_nil
    end
  end

  describe ".from_file" do
    let(:yaml_content) do
      <<~YAML
        translations:
          - path/to/Localizable.strings
          - path/to/strings.xml

        source:
          paths:
            - ./Sources
            - ./App
          ignore:
            - "**/Generated/**"
            - "**/*.test.swift"

        llm:
          provider: anthropic
          model: claude-3-haiku

        processing:
          concurrency: 8
          context_lines: 15
          max_matches_per_key: 5

        output:
          path: context.csv
          format: csv
          write_back: true
          context_prefix: ""
          context_mode: append

        prompt: |
          Custom prompt here
      YAML
    end

    let(:config_path) { File.join(Dir.tmpdir, "test_txcontext.yml") }

    before do
      File.write(config_path, yaml_content)
    end

    after do
      File.delete(config_path) if File.exist?(config_path)
    end

    it "loads configuration from YAML file" do
      config = described_class.from_file(config_path)

      expect(config.translations).to eq(["path/to/Localizable.strings", "path/to/strings.xml"])
      expect(config.source_paths).to eq(["./Sources", "./App"])
      expect(config.ignore_patterns).to eq(["**/Generated/**", "**/*.test.swift"])
      expect(config.provider).to eq("anthropic")
      expect(config.model).to eq("claude-3-haiku")
      expect(config.concurrency).to eq(8)
      expect(config.context_lines).to eq(15)
      expect(config.max_matches_per_key).to eq(5)
      expect(config.output_path).to eq("context.csv")
      expect(config.write_back).to be true
      expect(config.context_prefix).to eq("")
      expect(config.context_mode).to eq("append")
      expect(config.custom_prompt).to include("Custom prompt")
    end

    it "handles translations as hash with path key" do
      yaml_with_hash = <<~YAML
        translations:
          - path: Localizable.strings
            format: strings
      YAML

      File.write(config_path, yaml_with_hash)
      config = described_class.from_file(config_path)

      expect(config.translations).to eq(["Localizable.strings"])
    end
  end

  describe ".from_cli" do
    it "parses CLI options" do
      options = {
        translations: "file1.strings,file2.strings",
        source: "./Sources,./App",
        provider: "anthropic",
        model: "claude-3-opus",
        concurrency: 3,
        output: "output.csv",
        format: "json",
        cache: true,
        dry_run: true,
        keys: "key1,key2",
        write_back: true,
        diff_base: "origin/main",
        context_prefix: "Note: ",
        context_mode: "append"
      }

      config = described_class.from_cli(options)

      expect(config.translations).to eq(["file1.strings", "file2.strings"])
      expect(config.source_paths).to eq(["./Sources", "./App"])
      expect(config.provider).to eq("anthropic")
      expect(config.model).to eq("claude-3-opus")
      expect(config.concurrency).to eq(3)
      expect(config.output_path).to eq("output.csv")
      expect(config.output_format).to eq("json")
      expect(config.no_cache).to be false
      expect(config.dry_run).to be true
      expect(config.key_filter).to eq("key1,key2")
      expect(config.write_back).to be true
      expect(config.diff_base).to eq("origin/main")
      expect(config.context_prefix).to eq("Note: ")
      expect(config.context_mode).to eq("append")
    end

    it "uses defaults for missing options" do
      config = described_class.from_cli({})

      expect(config.translations).to eq([])
      expect(config.source_paths).to eq(["."])
      expect(config.no_cache).to be true
      expect(config.dry_run).to be false
    end
  end

  describe "#merge_cli" do
    let(:base_config) do
      described_class.new(
        translations: ["base.strings"],
        output_path: "base.csv",
        no_cache: false,
        concurrency: 5
      )
    end

    it "overrides config with CLI options" do
      options = {
        output: "override.csv",
        dry_run: true,
        concurrency: 10
      }

      merged = base_config.merge_cli(options)

      expect(merged.output_path).to eq("override.csv")
      expect(merged.dry_run).to be true
      expect(merged.concurrency).to eq(10)
      # Original values preserved when not overridden
      expect(merged.translations).to eq(["base.strings"])
    end

    it "returns self for chaining" do
      result = base_config.merge_cli({})

      expect(result).to be(base_config)
    end
  end

  describe ".default_ignore_patterns" do
    it "includes common patterns to ignore" do
      patterns = described_class.default_ignore_patterns

      expect(patterns).to include("**/node_modules/**")
      expect(patterns).to include("**/vendor/**")
      expect(patterns).to include("**/.git/**")
      expect(patterns).to include("**/build/**")
      expect(patterns).to include("**/*.test.*")
      expect(patterns).to include("**/*.spec.*")
    end
  end

  describe "#default_swift_functions" do
    it "includes common Swift localization functions" do
      config = described_class.new

      expect(config.swift_functions).to include("NSLocalizedString")
      expect(config.swift_functions).to include("String(localized:")
      expect(config.swift_functions).to include("Text(")
    end
  end
end
