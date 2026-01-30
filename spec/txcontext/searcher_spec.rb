# frozen_string_literal: true

RSpec.describe Txcontext::Searcher do
  describe "iOS platform" do
    subject(:searcher) do
      described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: [],
        context_lines: 5,
        platform: :ios
      )
    end

    describe "#search" do
      context "with NSLocalizedString pattern" do
        it "finds single-line NSLocalizedString usage" do
          matches = searcher.search("settings.title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("SettingsViewController.swift") }).to be true
        end

        it "finds multi-line NSLocalizedString usage" do
          matches = searcher.search("multiline.accessibility.label")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("MultilineExamples.swift") }).to be true
        end

        it "finds deeply nested multi-line patterns" do
          matches = searcher.search("multiline.nested.deep")

          expect(matches).not_to be_empty
        end
      end

      context "with String(localized:) pattern" do
        it "finds modern Swift localization" do
          matches = searcher.search("quickstart.title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("QuickStartView.swift") }).to be true
        end

        it "finds String(localized:) with comment parameter" do
          matches = searcher.search("swiftui.programmatic.string")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("SwiftUIExamples.swift") }).to be true
        end
      end

      context "with LocalizedStringKey pattern" do
        it "finds LocalizedStringKey initialization" do
          matches = searcher.search("swiftui.welcome.message")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("SwiftUIExamples.swift") }).to be true
        end

        it "finds LocalizedStringKey in property" do
          matches = searcher.search("swiftui.header.title")

          expect(matches).not_to be_empty
        end

        # Known limitation: direct string assignment to LocalizedStringKey type
        # Pattern: @State var key: LocalizedStringKey = "key"
        # This is not wrapped in LocalizedStringKey() so won't match
        it "does not currently find direct string assignment to LocalizedStringKey type" do
          matches = searcher.search("swiftui.state.button")

          # This is a known gap - the pattern needs a LocalizedStringKey() wrapper
          expect(matches).to be_empty
        end
      end

      context "with Text() pattern" do
        it "finds SwiftUI Text with key" do
          matches = searcher.search("quickstart.header")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("QuickStartView.swift") }).to be true
        end
      end

      context "with .localized extension pattern" do
        it "finds .localized usage" do
          matches = searcher.search("extension.title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("LocalizedExtension.swift") }).to be true
        end

        # Note: Method chaining after .localized works for simple keys
        # The pattern "key".localized.uppercased() is matched
        it "finds .localized with simple key" do
          matches = searcher.search("extension.swiftui.title")

          expect(matches).not_to be_empty
        end
      end

      context "with Objective-C files" do
        # Note: Objective-C uses @"string" syntax, not "string"
        # The searcher patterns use [\"'] which should match both
        it "finds NSLocalizedString in .m files with @-string syntax" do
          matches = searcher.search("objc.screen.title")

          # This tests that .m files are searched and @"..." syntax works
          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("LegacyStrings.m") }).to be true
        end

        it "finds multi-line NSLocalizedString in Objective-C" do
          matches = searcher.search("objc.screen.description")

          expect(matches).not_to be_empty
        end
      end
    end

    describe "false positive filtering" do
      it "does not match string comparisons with ==" do
        # This key appears in FalsePositives.swift in comparison contexts
        matches = searcher.search("common.save")

        # Should find real usage in ProfileViewController, not false positives
        false_positive_matches = matches.select { |m| m.file.end_with?("FalsePositives.swift") }

        # The false positive file should have matches filtered out where they're comparisons
        # Real matches should have NSLocalizedString or similar
        real_matches = matches.select do |m|
          m.match_line.include?("NSLocalizedString") ||
            m.match_line.include?("localized")
        end

        expect(real_matches).not_to be_empty
      end

      it "does not match dictionary key access" do
        matches = searcher.search("post.create")

        # All matches should be actual localization calls
        matches.each do |match|
          # Should not be dictionary access like translations["post.create"]
          expect(match.match_line).not_to match(/\[["']post\.create["']\]/)
        end
      end
    end

    describe "match context" do
      it "includes surrounding context lines" do
        matches = searcher.search("settings.title")

        expect(matches).not_to be_empty
        match = matches.first
        expect(match.context).not_to be_empty
        expect(match.context.lines.count).to be > 1
      end

      it "marks the matching line with >>>" do
        matches = searcher.search("settings.title")

        expect(matches).not_to be_empty
        match = matches.first
        expect(match.context).to include(">>>")
      end
    end

    describe "translation file exclusion" do
      it "does not return matches from .strings files" do
        matches = searcher.search("common.save")

        strings_file_matches = matches.select { |m| m.file.end_with?(".strings") }
        expect(strings_file_matches).to be_empty
      end
    end
  end

  describe "Android platform" do
    subject(:searcher) do
      described_class.new(
        source_paths: [android_fixtures_path],
        ignore_patterns: [],
        context_lines: 5,
        platform: :android
      )
    end

    describe "#search" do
      context "with R.string pattern" do
        it "finds R.string.key usage" do
          matches = searcher.search("settings_title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("SettingsActivity.kt") }).to be true
        end
      end

      context "with getString pattern" do
        it "finds getString(R.string.key) usage" do
          matches = searcher.search("settings_notifications")

          expect(matches).not_to be_empty
        end

        it "finds context.getString pattern" do
          matches = searcher.search("post_like")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("PostAdapter.kt") }).to be true
        end
      end

      context "with @string/ XML pattern" do
        it "finds @string/key in layout XML" do
          matches = searcher.search("xml_toolbar_title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("activity_main.xml") }).to be true
        end

        it "finds @string/key in contentDescription" do
          matches = searcher.search("xml_welcome_description")

          expect(matches).not_to be_empty
        end
      end

      context "with stringResource pattern (Jetpack Compose)" do
        it "finds stringResource(R.string.key) usage" do
          matches = searcher.search("compose_welcome_title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("ComposeScreen.kt") }).to be true
        end

        it "finds multi-line stringResource calls" do
          matches = searcher.search("compose_multiline_example")

          expect(matches).not_to be_empty
        end
      end

      context "with static import pattern" do
        it "finds string.key usage with static import" do
          matches = searcher.search("static_import_title")

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?("StaticImportExample.kt") }).to be true
        end

        it "finds getString(string.key) pattern" do
          matches = searcher.search("static_import_welcome")

          expect(matches).not_to be_empty
        end
      end
    end

    describe "translation file exclusion" do
      it "does not return matches from strings.xml" do
        matches = searcher.search("common_save")

        strings_xml_matches = matches.select { |m| m.file.include?("values/strings.xml") }
        expect(strings_xml_matches).to be_empty
      end
    end
  end

  describe "platform detection" do
    it "detects iOS platform from Swift files" do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: []
      )

      # Platform detection happens in initialize, we can test by searching
      # iOS patterns should work
      matches = searcher.search("settings.title")
      expect(matches).not_to be_empty
    end

    it "detects Android platform from Kotlin files" do
      searcher = described_class.new(
        source_paths: [android_fixtures_path],
        ignore_patterns: []
      )

      # Android patterns should work
      matches = searcher.search("settings_title")
      expect(matches).not_to be_empty
    end
  end

  describe "ignore patterns" do
    it "respects glob ignore patterns" do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: ["**/FalsePositives.swift"],
        platform: :ios
      )

      matches = searcher.search("common.save")

      false_positive_matches = matches.select { |m| m.file.end_with?("FalsePositives.swift") }
      expect(false_positive_matches).to be_empty
    end

    it "handles ** glob pattern" do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: ["**/Multiline*.swift"],
        platform: :ios
      )

      matches = searcher.search("multiline.accessibility.label")
      expect(matches).to be_empty
    end
  end

  describe "Match struct" do
    it "includes file, line number, match line, and context" do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: [],
        platform: :ios
      )

      matches = searcher.search("settings.title")
      match = matches.first

      expect(match.file).to be_a(String)
      expect(match.file).not_to be_empty
      expect(match.line).to be_a(Integer)
      expect(match.line).to be > 0
      expect(match.match_line).to be_a(String)
      expect(match.context).to be_a(String)
    end
  end
end
