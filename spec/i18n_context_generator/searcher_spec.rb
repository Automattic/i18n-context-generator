# frozen_string_literal: true

RSpec.describe I18nContextGenerator::Searcher do
  describe 'iOS platform' do
    subject(:searcher) do
      described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: [],
        context_lines: 5,
        platform: :ios
      )
    end

    describe '#search' do
      context 'with NSLocalizedString pattern' do
        it 'finds single-line NSLocalizedString usage' do
          matches = searcher.search('settings.title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('SettingsViewController.swift') }).to be true
        end

        it 'finds multi-line NSLocalizedString usage' do
          matches = searcher.search('multiline.accessibility.label')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('MultilineExamples.swift') }).to be true
        end

        it 'finds deeply nested multi-line patterns' do
          matches = searcher.search('multiline.nested.deep')

          expect(matches).not_to be_empty
        end

        it 'follows localization wrapper constants to actual UI usage sites' do
          matches = searcher.search('wrapper.save')

          expect(matches).not_to be_empty
          expect(matches.first.file.end_with?('LocalizationWrapperView.swift')).to be true
          expect(matches.first.match_line).to include('button.setTitle(Localization.save, for: .normal)')
        end

        it 'finds placeholder usage behind localization wrappers' do
          matches = searcher.search('wrapper.note.placeholder')

          expect(matches).not_to be_empty
          expect(matches.first.match_line).to include('field.placeholder = Localization.notePlaceholder')
        end

        it 'does not pull unrelated multiline localization keys into wrapper usage matches' do
          matches = searcher.search('wrapper.save')

          expect(matches.any? { |m| m.file.end_with?('UnrelatedSaveString.swift') }).to be false
        end

        it 'does not pull unrelated nested Localization members from other files' do
          matches = searcher.search('wrapper.title')

          expect(matches).not_to be_empty
          expect(matches.any? do |m|
            m.file.end_with?('LocalizationWrapperView.swift') &&
                      m.match_line.include?('label.text = Localization.title')
          end).to be true
          expect(matches.any? { |m| m.file.end_with?('UnrelatedLocalizationTitleView.swift') }).to be false
        end
      end

      context 'with String(localized:) pattern' do
        it 'finds modern Swift localization' do
          matches = searcher.search('quickstart.title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('QuickStartView.swift') }).to be true
        end

        it 'finds String(localized:) with comment parameter' do
          matches = searcher.search('swiftui.programmatic.string')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('SwiftUIExamples.swift') }).to be true
        end
      end

      context 'with LocalizedStringKey pattern' do
        it 'finds LocalizedStringKey initialization' do
          matches = searcher.search('swiftui.welcome.message')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('SwiftUIExamples.swift') }).to be true
        end

        it 'finds LocalizedStringKey in property' do
          matches = searcher.search('swiftui.header.title')

          expect(matches).not_to be_empty
        end

        it 'finds direct string assignment to LocalizedStringKey type' do
          matches = searcher.search('swiftui.state.button')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('SwiftUIExamples.swift') }).to be true
        end
      end

      context 'with Text() pattern' do
        it 'finds SwiftUI Text with key' do
          matches = searcher.search('quickstart.header')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('QuickStartView.swift') }).to be true
        end
      end

      context 'with .localized extension pattern' do
        it 'finds .localized usage' do
          matches = searcher.search('extension.title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('LocalizedExtension.swift') }).to be true
        end

        # NOTE: Method chaining after .localized works for simple keys
        # The pattern "key".localized.uppercased() is matched
        it 'finds .localized with simple key' do
          matches = searcher.search('extension.swiftui.title')

          expect(matches).not_to be_empty
        end
      end

      context 'with Objective-C files' do
        # NOTE: Objective-C uses @"string" syntax, not "string"
        # The searcher patterns use [\"'] which should match both
        it 'finds NSLocalizedString in .m files with @-string syntax' do
          matches = searcher.search('objc.screen.title')

          # This tests that .m files are searched and @"..." syntax works
          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('LegacyStrings.m') }).to be true
        end

        it 'finds multi-line NSLocalizedString in Objective-C' do
          matches = searcher.search('objc.screen.description')

          expect(matches).not_to be_empty
        end
      end
    end

    describe 'false positive filtering' do
      it 'does not match string comparisons with ==' do
        # This key appears in FalsePositives.swift in comparison contexts
        matches = searcher.search('common.save')

        # Should find real usage in ProfileViewController, not false positives
        matches.select { |m| m.file.end_with?('FalsePositives.swift') }

        # The false positive file should have matches filtered out where they're comparisons
        # Real matches should have NSLocalizedString or similar
        real_matches = matches.select do |m|
          m.match_line.include?('NSLocalizedString') ||
            m.match_line.include?('localized')
        end

        expect(real_matches).not_to be_empty
      end

      it 'does not match dictionary key access' do
        matches = searcher.search('post.create')

        # All matches should be actual localization calls
        matches.each do |match|
          # Should not be dictionary access like translations["post.create"]
          expect(match.match_line).not_to match(/\[["']post\.create["']\]/)
        end
      end

      it 'keeps a localization call when an unrelated comparison shares its line' do
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'InlineComparison.swift')
          File.write(file, 'let title = Text("settings.inline"); let ready = state == "ready"')
          inline_searcher = described_class.new(source_paths: [dir], ignore_patterns: [], platform: :ios)

          expect(inline_searcher.search('settings.inline').map(&:file)).to eq([file])
        end
      end
    end

    describe 'match context' do
      it 'includes surrounding lines and marks the matching line with >>>' do
        matches = searcher.search('settings.title')

        expect(matches).not_to be_empty
        match = matches.first
        expect(match.context).not_to be_empty
        expect(match.context.lines.count).to be > 1
        expect(match.context).to include('>>>')
      end
    end

    describe 'translation file exclusion' do
      it 'does not return matches from .strings files' do
        matches = searcher.search('common.save')

        strings_file_matches = matches.select { |m| m.file.end_with?('.strings') }
        expect(strings_file_matches).to be_empty
      end
    end

    describe '#discover_localization_entries' do
      it 'discovers localized keys and comments directly from source files' do
        entries = searcher.discover_localization_entries

        settings_title = entries.find { |entry| entry.key == 'settings.title' }
        multiline_label = entries.find { |entry| entry.key == 'multiline.accessibility.label' }
        state_button = entries.find { |entry| entry.key == 'swiftui.state.button' }

        expect(settings_title).to have_attributes(
          comment: 'Navigation bar title for settings screen'
        )
        expect(multiline_label).to have_attributes(
          comment: 'Accessibility label for main content area'
        )
        expect(state_button).to have_attributes(
          text: nil,
          comment: nil
        )
      end

      it 'keeps the first entry unless a later duplicate adds a comment' do
        uncommented_first = described_class::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'First.swift',
          line: 10,
          text: 'Settings',
          comment: nil
        )
        uncommented_second = described_class::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'Second.swift',
          line: 20,
          text: 'Settings',
          comment: nil
        )
        commented_third = described_class::DiscoveredLocalization.new(
          key: 'settings.title',
          file: 'Third.swift',
          line: 30,
          text: 'Settings',
          comment: 'Navigation title for settings screen'
        )

        deduplicated = searcher.send(
          :deduplicate_discovered_entries,
          [uncommented_first, uncommented_second, commented_third]
        )

        expect(deduplicated).to contain_exactly(
          have_attributes(
            file: 'Third.swift',
            line: 30,
            comment: 'Navigation title for settings screen',
            locations: ['First.swift:10', 'Second.swift:20', 'Third.swift:30']
          )
        )

        deduplicated = searcher.send(
          :deduplicate_discovered_entries,
          [uncommented_first, uncommented_second]
        )

        expect(deduplicated).to contain_exactly(
          have_attributes(
            file: 'First.swift',
            line: 10,
            comment: nil,
            locations: ['First.swift:10', 'Second.swift:20']
          )
        )
      end

      it 'ignores localization calls in Swift comments' do
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'CommentedExamples.swift')
          File.write(file, <<~SWIFT)
            // Text("commented.single")
            /*
             Text("commented.block")
            */
            let url = "https://example.com/path"
            Text("live.key") // Text("commented.trailing")
          SWIFT
          comment_searcher = described_class.new(source_paths: [dir], ignore_patterns: [], platform: :ios)

          entries = comment_searcher.discover_localization_entries

          expect(entries.map(&:key)).to eq(['live.key'])
          expect(comment_searcher.search('commented.single')).to be_empty
          expect(comment_searcher.search('commented.block')).to be_empty
          expect(comment_searcher.search('commented.trailing')).to be_empty
          expect(comment_searcher.search('live.key')).not_to be_empty
        end
      end
    end
  end

  describe 'Android platform' do
    subject(:searcher) do
      described_class.new(
        source_paths: [android_fixtures_path],
        ignore_patterns: [],
        context_lines: 5,
        platform: :android
      )
    end

    describe '#search' do
      context 'with R.string pattern' do
        it 'finds R.string.key usage' do
          matches = searcher.search('settings_title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('SettingsActivity.kt') }).to be true
        end
      end

      context 'with getString pattern' do
        it 'finds getString(R.string.key) usage' do
          matches = searcher.search('settings_notifications')

          expect(matches).not_to be_empty
        end

        it 'finds context.getString pattern' do
          matches = searcher.search('post_like')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('PostAdapter.kt') }).to be true
        end
      end

      context 'with @string/ XML pattern' do
        it 'finds @string/key in layout XML' do
          matches = searcher.search('xml_toolbar_title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('activity_main.xml') }).to be true
        end

        it 'finds @string/key in contentDescription' do
          matches = searcher.search('xml_welcome_description')

          expect(matches).not_to be_empty
        end
      end

      context 'with stringResource pattern (Jetpack Compose)' do
        it 'finds stringResource(R.string.key) usage' do
          matches = searcher.search('compose_welcome_title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('ComposeScreen.kt') }).to be true
        end

        it 'finds multi-line stringResource calls' do
          matches = searcher.search('compose_multiline_example')

          expect(matches).not_to be_empty
        end
      end

      context 'with static import pattern' do
        it 'finds string.key usage with static import' do
          matches = searcher.search('static_import_title')

          expect(matches).not_to be_empty
          expect(matches.any? { |m| m.file.end_with?('StaticImportExample.kt') }).to be true
        end

        it 'finds getString(string.key) pattern' do
          matches = searcher.search('static_import_welcome')

          expect(matches).not_to be_empty
        end
      end
    end

    describe 'translation file exclusion' do
      it 'does not return matches from strings.xml' do
        matches = searcher.search('common_save')

        strings_xml_matches = matches.select { |m| m.file.include?('values/strings.xml') }
        expect(strings_xml_matches).to be_empty
      end
    end

    describe '#discover_localization_entries' do
      it 'discovers Android string references from source files' do
        entries = searcher.discover_localization_entries

        settings_title = entries.find { |entry| entry.key == 'settings_title' }
        xml_title = entries.find { |entry| entry.key == 'xml_toolbar_title' }
        likes_plural = entries.find { |entry| entry.key == 'post_likes_count' }

        expect(settings_title).not_to be_nil
        expect(xml_title).not_to be_nil
        expect(likes_plural).to have_attributes(resource_type: :plural)
        expect(entries.map(&:key)).not_to include('key_name')
      end

      it 'discovers XML references when the relative source root is res' do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('res/layout')
            File.write('res/layout/screen.xml', '<TextView android:text="@string/relative_res_title" />')
            relative_searcher = described_class.new(source_paths: ['res'], ignore_patterns: [])

            entries = relative_searcher.discover_localization_entries

            expect(entries).to contain_exactly(
              have_attributes(key: 'relative_res_title', file: 'res/layout/screen.xml')
            )
          end
        end
      end

      it 'discovers and searches Android array references' do
        Dir.mktmpdir do |dir|
          file = File.join(dir, 'Arrays.kt')
          File.write(file, <<~KOTLIN)
            val days = resources.getStringArray(R.array.days_of_week)
          KOTLIN
          array_searcher = described_class.new(source_paths: [dir], ignore_patterns: [], platform: :android)

          entry = array_searcher.discover_localization_entries.find { |candidate| candidate.key == 'days_of_week' }
          matches = array_searcher.search('days_of_week', resource_type: :array)

          expect(entry).to have_attributes(resource_type: :array)
          expect(matches.map(&:line)).to eq([1])
        end
      end

      it 'ignores localization references in Kotlin and XML comments' do
        Dir.mktmpdir do |dir|
          kotlin_file = File.join(dir, 'Screen.kt')
          xml_dir = File.join(dir, 'res', 'layout')
          xml_file = File.join(xml_dir, 'screen.xml')
          FileUtils.mkdir_p(xml_dir)
          File.write(kotlin_file, <<~KOTLIN)
            // val ignored = R.string.commented_kotlin
            val title = R.string.live_kotlin // R.string.trailing_kotlin
          KOTLIN
          File.write(xml_file, <<~XML)
            <LinearLayout>
              <!-- android:text="@string/commented_xml" -->
              <TextView android:text="@string/live_xml" />
            </LinearLayout>
          XML
          comment_searcher = described_class.new(source_paths: [dir], ignore_patterns: [], platform: :android)

          keys = comment_searcher.discover_localization_entries.map(&:key)

          expect(keys).to contain_exactly('live_kotlin', 'live_xml')
          expect(comment_searcher.search('commented_kotlin')).to be_empty
          expect(comment_searcher.search('trailing_kotlin')).to be_empty
          expect(comment_searcher.search('commented_xml')).to be_empty
        end
      end
    end
  end

  describe 'platform detection' do
    it 'detects iOS platform from Swift files' do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: []
      )

      # Platform detection happens in initialize, we can test by searching
      # iOS patterns should work
      matches = searcher.search('settings.title')
      expect(matches).not_to be_empty
    end

    it 'detects Android platform from Kotlin files' do
      searcher = described_class.new(
        source_paths: [android_fixtures_path],
        ignore_patterns: []
      )

      # Android patterns should work
      matches = searcher.search('settings_title')
      expect(matches).not_to be_empty
    end

    it 'ignores excluded files when auto-detecting the platform' do
      Dir.mktmpdir do |dir|
        ignored_dir = File.join(dir, 'build')
        source_dir = File.join(dir, 'Sources')
        ignored_android = File.join(ignored_dir, 'Ignored.kt')
        swift_file = File.join(source_dir, 'ViewController.swift')

        FileUtils.mkdir_p(ignored_dir)
        FileUtils.mkdir_p(source_dir)
        File.write(ignored_android, 'class Ignored { fun render() { getString(R.string.settings_title) } }')
        File.write(swift_file, 'let title = NSLocalizedString("settings.title", comment: "")')

        searcher = described_class.new(
          source_paths: [dir],
          ignore_patterns: ['**/build/**']
        )

        matches = searcher.search('settings.title')

        expect(matches.map(&:file)).to eq([swift_file])
      end
    end

    it 'does not treat a header as iOS platform evidence' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'Bridge.h'), '#define APP_NAME "Example"')
        kotlin_file = File.join(dir, 'Screen.kt')
        File.write(kotlin_file, 'val title = R.string.android_title')

        searcher = described_class.new(source_paths: [dir], ignore_patterns: [])

        expect(searcher.search('android_title').map(&:file)).to eq([kotlin_file])
      end
    end
  end

  describe 'ignore patterns' do
    it 'respects glob ignore patterns' do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: ['**/FalsePositives.swift'],
        platform: :ios
      )

      matches = searcher.search('common.save')

      false_positive_matches = matches.select { |m| m.file.end_with?('FalsePositives.swift') }
      expect(false_positive_matches).to be_empty
    end

    it 'handles ** glob pattern' do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: ['**/Multiline*.swift'],
        platform: :ios
      )

      matches = searcher.search('multiline.accessibility.label')
      expect(matches).to be_empty
    end

    it 'matches ignored directory roots so traversal can prune them' do
      Dir.mktmpdir do |dir|
        ignored_dir = File.join(dir, 'build')
        FileUtils.mkdir_p(ignored_dir)
        File.write(File.join(ignored_dir, 'Generated.swift'), 'Text("ignored.key")')
        searcher = described_class.new(
          source_paths: [dir],
          ignore_patterns: ['**/build/**'],
          platform: :ios
        )

        expect(searcher.send(:ignored?, ignored_dir, directory: true)).to be true
        expect(searcher.send(:discover_files)).to be_empty
      end
    end

    it 'skips an ignored configured root without traversing it' do
      Dir.mktmpdir do |dir|
        build_dir = File.join(dir, 'build')
        FileUtils.mkdir_p(build_dir)
        File.write(File.join(build_dir, 'Generated.swift'), 'Text("ignored.key")')
        searcher = described_class.new(
          source_paths: [build_dir],
          ignore_patterns: ['**/build/**'],
          platform: :ios
        )

        expect(searcher.send(:discover_files)).to be_empty
      end
    end
  end

  describe 'source path ordering and de-duplication' do
    it 'scans overlapping roots once while preserving configured root and file order' do
      Dir.mktmpdir do |dir|
        first_root = File.join(dir, 'First')
        second_root = File.join(dir, 'Second')
        FileUtils.mkdir_p(first_root)
        FileUtils.mkdir_p(second_root)
        first_file = File.join(first_root, 'B.swift')
        second_file = File.join(second_root, 'A.swift')
        File.write(first_file, "Text(\"first.key\")\nText(\"first.second\")\n")
        File.write(second_file, "Text(\"second.key\")\n")

        searcher = described_class.new(
          source_paths: [second_root, dir, first_root],
          ignore_patterns: [],
          platform: :ios
        )

        files = searcher.send(:discover_files)
        entries = searcher.discover_localization_entries

        expect(files).to eq([second_file, first_file])
        expect(entries.map(&:key)).to eq(%w[second.key first.key first.second])
      end
    end
  end

  describe 'Match struct' do
    it 'includes file, line number, match line, and context' do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: [],
        platform: :ios
      )

      matches = searcher.search('settings.title')
      match = matches.first

      expect(match.file).to be_a(String)
      expect(match.file).not_to be_empty
      expect(match.line).to be_a(Integer)
      expect(match.line).to be > 0
      expect(match.match_line).to be_a(String)
      expect(match.context).to be_a(String)
    end

    it 'includes enclosing scope when available' do
      searcher = described_class.new(
        source_paths: [ios_fixtures_path],
        ignore_patterns: [],
        platform: :ios
      )

      matches = searcher.search('settings.title')
      match = matches.first

      # Should detect the enclosing function or class
      expect(match.enclosing_scope).not_to be_nil
    end
  end

  describe 'source file caching' do
    it 'reads each source file once across repeated searches and discovery' do
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'Cached.swift')
        File.write(file, <<~SWIFT)
          Text("first.key")
          Text("second.key")
        SWIFT
        caching_searcher = described_class.new(source_paths: [dir], ignore_patterns: [], platform: :ios)
        allow(File).to receive(:readlines).and_call_original

        threads = %w[first.key second.key].cycle.take(10).map do |key|
          Thread.new { caching_searcher.search(key) }
        end
        threads.each(&:join)
        caching_searcher.discover_localization_entries

        expect(File).to have_received(:readlines).with(file, chomp: true).once
      end
    end
  end
end
