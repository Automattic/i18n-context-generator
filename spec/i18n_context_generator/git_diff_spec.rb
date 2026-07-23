# frozen_string_literal: true

RSpec.describe I18nContextGenerator::GitDiff do
  describe 'explicit ranges' do
    it 'diffs the configured base and head refs' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, "\"existing\" = \"Existing\";\n")
        status = instance_double(Process::Status, success?: true)
        diff_output = <<~DIFF
          @@ -1,1 +1,4 @@
           "existing" = "Existing";
          +"save.button" = "Save";
          +"cart+cta" = "Cart";
          +"key,with,commas" = "Commas";
        DIFF

        allow(Open3).to receive(:capture3).and_return([diff_output, '', status])

        keys = described_class.new(base_ref: 'danger_base', head_ref: 'danger_head').changed_keys([path])
        locations = described_class.new(
          base_ref: 'danger_base', head_ref: 'danger_head'
        ).changed_key_locations([path])

        expect(keys).to eq(Set['save.button', 'cart+cta', 'key,with,commas'])
        expect(locations).to eq(
          [path, 'save.button'] => [
            I18nContextGenerator::ChangedLocation.new(file: path, line: 2)
          ],
          [path, 'cart+cta'] => [
            I18nContextGenerator::ChangedLocation.new(file: path, line: 3)
          ],
          [path, 'key,with,commas'] => [
            I18nContextGenerator::ChangedLocation.new(file: path, line: 4)
          ]
        )
        expect(Open3).to have_received(:capture3).with(
          'git', 'diff', 'danger_base...danger_head', '--', 'Localizable.strings', chdir: dir
        ).twice
      end
    end

    it 'raises an actionable error when git diff fails' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.strings')
        File.write(path, "\"existing\" = \"Existing\";\n")
        status = instance_double(Process::Status, success?: false)

        allow(Open3).to receive(:capture3).and_return(['', 'fatal: bad revision', status])

        diff = described_class.new(base_ref: 'danger_base', head_ref: 'danger_head')

        expect { diff.changed_keys([path]) }.to raise_error(
          I18nContextGenerator::Error,
          /Git diff failed for danger_base\.\.\.danger_head.*fatal: bad revision/
        )
      end
    end

    it 'projects typed Android XML locations through the public key API' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'strings.xml')
        File.write(path, <<~XML)
          <resources>
            <string name="existing">Existing</string>
            <string name="new_key">New</string>
          </resources>
        XML
        status = instance_double(Process::Status, success?: true)
        diff_output = <<~DIFF
          diff --git a/strings.xml b/strings.xml
          index abc1234..def5678 100644
          --- a/strings.xml
          +++ b/strings.xml
          @@ -1,3 +1,4 @@
           <resources>
             <string name="existing">Existing</string>
          +  <string name="new_key">New</string>
           </resources>
        DIFF
        allow(Open3).to receive(:capture3).and_return([diff_output, '', status])
        diff = described_class.new(base_ref: 'danger_base', head_ref: 'danger_head')

        expect(diff.changed_keys([path])).to eq(Set['new_key'])
        expect(diff.changed_key_locations([path])).to eq(
          [path, 'new_key'] => [
            I18nContextGenerator::ChangedLocation.new(file: path, line: 3)
          ]
        )
      end
    end
  end

  describe '#changed_lines' do
    it 'detects changed source line numbers for files in nested directories' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          system('git', 'init', '-q', '-b', 'main')
          FileUtils.mkdir_p('ios/App')
          path = File.join('ios', 'App', 'SettingsView.swift')

          File.write(path, <<~SWIFT)
            struct SettingsView {
              var body: some View {
                Text("existing")
              }
            }
          SWIFT
          system('git', 'add', path)
          system('git', '-c', 'user.name=i18n-context-generator', '-c', 'user.email=i18n-context-generator@example.com',
                 'commit', '-q', '-m', 'Initial commit')
          system('git', 'checkout', '-q', '-b', 'feature')

          File.write(path, <<~SWIFT)
            struct SettingsView {
              var body: some View {
                Text("existing")
                Text("new.settings.title")
              }
            }
          SWIFT
          system('git', 'add', path)
          system('git', '-c', 'user.name=i18n-context-generator', '-c', 'user.email=i18n-context-generator@example.com',
                 'commit', '-q', '-m', 'Add localized string')

          diff = described_class.new(base_ref: 'main')
          changed_lines = diff.changed_lines(['./ios/App'])
          root_changed_lines = diff.changed_lines(['.'])
          absolute_source_path = File.join(dir, 'ios', 'App')
          absolute_changed_lines = diff.changed_lines([absolute_source_path])

          expect(changed_lines.fetch(path)).to include(4)
          expect(root_changed_lines.fetch(path)).to include(4)
          expect(absolute_changed_lines.fetch(File.join(absolute_source_path, 'SettingsView.swift'))).to include(4)
          expect(absolute_changed_lines.keys).not_to include(
            File.join(absolute_source_path, 'ios', 'App', 'SettingsView.swift')
          )
        end
      end
    end

    it 'keeps added content that resembles a diff file header' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'script.rb')
        File.write(path, "++ added content\n")
        status = instance_double(Process::Status, success?: true)
        diff_output = <<~DIFF
          diff --git a/script.rb b/script.rb
          index abc1234..def5678 100644
          --- a/script.rb
          +++ b/script.rb
          @@ -10 +10 @@
          --- removed content
          +++ added content
        DIFF
        allow(Open3).to receive(:capture3).and_return([diff_output, '', status])

        changed_lines = described_class.new(base_ref: 'main').changed_lines([path])

        expect(changed_lines.fetch(path)).to eq(Set[10])
      end
    end
  end

  describe 'changed diff line iteration' do
    it 'keeps removed and added content that resembles diff file headers' do
      diff_output = <<~DIFF
        diff --git a/example.txt b/example.txt
        --- a/example.txt
        +++ b/example.txt
        @@ -10 +10 @@
        --- removed content
        +++ added content
      DIFF
      changes = []

      described_class.new.send(:each_changed_diff_line, diff_output) do |content, old_line, new_line, side|
        changes << [content.chomp, old_line, new_line, side]
      end

      expect(changes).to eq(
        [
          ['-- removed content', 10, nil, :left],
          ['++ added content', nil, 10, :right]
        ]
      )
    end
  end

  describe '#changed_keys' do
    it 'detects changes for translation files in nested directories' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          system('git', 'init', '-q', '-b', 'main')
          FileUtils.mkdir_p('ios/App/Resources')
          path = File.join('ios', 'App', 'Resources', 'Localizable.strings')

          File.write(path, "\"existing\" = \"Old\";\n")
          system('git', 'add', path)
          system('git', '-c', 'user.name=i18n-context-generator', '-c', 'user.email=i18n-context-generator@example.com',
                 'commit', '-q', '-m', 'Initial commit')
          system('git', 'checkout', '-q', '-b', 'feature')

          File.write(path, "\"existing\" = \"Updated\";\n\"new.key\" = \"New\";\n")
          system('git', 'add', path)
          system('git', '-c', 'user.name=i18n-context-generator', '-c', 'user.email=i18n-context-generator@example.com',
                 'commit', '-q', '-m', 'Update translations')

          diff = described_class.new(base_ref: 'main')
          keys = diff.changed_keys([path])

          expect(keys).to include('existing', 'new.key')
        end
      end
    end

    context 'with .strings diff' do
      it 'extracts added keys from .strings diff' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          diff --git a/Localizable.strings b/Localizable.strings
          index abc1234..def5678 100644
          --- a/Localizable.strings
          +++ b/Localizable.strings
          @@ -1,3 +1,5 @@
           "existing.key" = "Existing";
          +"new.key" = "New String";
          +"another.key" = "Another";
        DIFF

        keys = diff.send(
          :extract_strings_key_locations,
          diff_output,
          'Localizable.strings',
          head_content: <<~STRINGS
            "existing.key" = "Existing";
            "new.key" = "New String";
            "another.key" = "Another";
          STRINGS
        ).keys.to_set

        expect(keys).to include('new.key')
        expect(keys).to include('another.key')
        expect(keys).not_to include('existing.key')
      end

      it 'ignores removed lines' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -1,3 +1,2 @@
           "kept.key" = "Kept";
          -"removed.key" = "Removed";
          +"modified.key" = "Modified";
        DIFF

        keys = diff.send(
          :extract_strings_key_locations,
          diff_output,
          'Localizable.strings',
          head_content: <<~STRINGS
            "kept.key" = "Kept";
            "modified.key" = "Modified";
          STRINGS
        ).keys.to_set

        expect(keys).to include('modified.key')
        expect(keys).not_to include('removed.key')
        expect(keys).not_to include('kept.key')
      end

      it 'ignores diff header lines starting with ++' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          +++ b/Localizable.strings
          @@ -1,2 +1,3 @@
           "old" = "Old";
          +"real.key" = "Real";
        DIFF

        keys = diff.send(
          :extract_strings_key_locations,
          diff_output,
          'Localizable.strings',
          head_content: <<~STRINGS
            "old" = "Old";
            "real.key" = "Real";
          STRINGS
        ).keys.to_set

        expect(keys).to include('real.key')
        expect(keys.size).to eq(1)
      end

      it 'attributes a comment-only change to the following translation key' do
        diff = described_class.new(base_ref: 'main')

        Dir.mktmpdir do |dir|
          path = File.join(dir, 'Localizable.strings')
          File.write(path, "/* Better context */\n\"save.button\" = \"Save\";\n")
          diff_output = <<~DIFF
            @@ -1,2 +1,2 @@
            -/* Old context */
            +/* Better context */
             "save.button" = "Save";
          DIFF

          locations = diff.send(:extract_strings_key_locations, diff_output, path)

          expect(locations).to eq(
            'save.button' => [
              I18nContextGenerator::ChangedLocation.new(file: path, line: 1)
            ]
          )
        end
      end

      it 'decodes escaped quotes in changed keys' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~'DIFF'
          @@ -0,0 +1 @@
          +"quote\"key" = "Quoted";
        DIFF

        locations = diff.send(
          :extract_strings_key_locations,
          diff_output,
          'Localizable.strings',
          head_content: "\"quote\\\"key\" = \"Quoted\";\n"
        )

        expect(locations.keys).to eq(['quote"key'])
      end

      it 'retains the left side and a head fallback for a removed translator comment' do
        diff = described_class.new(base_ref: 'main')
        path = 'Localizable.strings'
        base_content = "/* Old context */\n\"save.button\" = \"Save\";\n"
        head_content = "\"save.button\" = \"Save\";\n"
        diff_output = <<~DIFF
          @@ -1,2 +1 @@
          -/* Old context */
           "save.button" = "Save";
        DIFF

        locations = diff.send(
          :extract_strings_key_locations,
          diff_output,
          path,
          base_content: base_content,
          head_content: head_content
        )

        expect(locations.fetch('save.button')).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(
            file: path,
            line: 1,
            side: :left,
            fallback_line: 1
          )
        )
      end
    end

    context 'with Android XML diff' do
      it 'extracts added <string> keys' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          diff --git a/strings.xml b/strings.xml
          --- a/strings.xml
          +++ b/strings.xml
          @@ -1,3 +1,5 @@
           <resources>
               <string name="existing">Existing</string>
          +    <string name="new_key">New String</string>
          +    <string name="another_key">Another</string>
           </resources>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('new_key')
        expect(keys).to include('another_key')
        expect(keys).not_to include('existing')
      end

      it 'supports reordered attributes, single quotes, and multiline opening tags' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -1,1 +1,5 @@
           <resources>
          +    <string translatable='true'
          +            formatted="false"
          +            name='flexible_key'>Flexible</string>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('flexible_key')
      end

      it 'distinguishes string arrays from string elements with multiline tags' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -1,1 +1,5 @@
           <resources>
          +    <string-array translatable='true'
          +                  name='weekdays'>
          +        <item>Monday</item>
          +    </string-array>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to eq(Set['weekdays'])
      end

      it 'extracts keys when entire plural block is added' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -5,0 +6,5 @@
          +    <plurals name="item_count">
          +        <item quantity="one">%d item</item>
          +        <item quantity="other">%d items</item>
          +    </plurals>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('item_count')
      end

      it 'tracks parent from context lines for changed items in plurals' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -5,4 +5,4 @@
               <plurals name="post_likes">
                   <item quantity="one">%d like</item>
          -        <item quantity="other">%d likes</item>
          +        <item quantity="other">%d total likes</item>
               </plurals>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('post_likes')
      end

      it 'maps changed collection items to their parent resource and changed line' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -5,4 +5,4 @@
               <plurals name="post_likes">
                   <item quantity="one">%d like</item>
          -        <item quantity="other">%d likes</item>
          +        <item quantity="other">%d total likes</item>
               </plurals>
        DIFF

        locations = diff.send(:extract_xml_key_locations, diff_output, 'res/values/strings.xml')

        expect(locations).to eq(
          'post_likes' => [
            I18nContextGenerator::ChangedLocation.new(
              file: 'res/values/strings.xml',
              line: 7
            )
          ]
        )
      end

      it 'tracks parent from context lines for changed items in string-array' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -10,4 +10,4 @@
               <string-array name="weekdays">
                   <item>Monday</item>
          -        <item>Tusday</item>
          +        <item>Tuesday</item>
               </string-array>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('weekdays')
      end

      it 'resets parent after closing tag' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -5,6 +5,7 @@
               <plurals name="old_plural">
                   <item quantity="one">one</item>
               </plurals>
          +    <string name="standalone">New standalone</string>
        DIFF

        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent').keys.to_set

        expect(keys).to include('standalone')
        expect(keys).not_to include('old_plural')
      end

      it 'attributes a changed translator comment to the following resource' do
        diff = described_class.new(base_ref: 'main')

        Dir.mktmpdir do |dir|
          path = File.join(dir, 'strings.xml')
          File.write(path, <<~XML)
            <resources>
              <!-- Better context -->
              <string name="save_button">Save</string>
            </resources>
          XML
          diff_output = <<~DIFF
            @@ -1,4 +1,4 @@
             <resources>
            -  <!-- Old context -->
            +  <!-- Better context -->
               <string name="save_button">Save</string>
             </resources>
          DIFF

          locations = diff.send(:extract_xml_key_locations, diff_output, path)

          expect(locations).to eq(
            'save_button' => [
              I18nContextGenerator::ChangedLocation.new(file: path, line: 2)
            ]
          )
        end
      end

      it 'ignores whitespace-only additions inside Android collections' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -1,4 +1,5 @@
           <resources>
             <plurals name="item_count">
          +
               <item quantity="one">One item</item>
             </plurals>
        DIFF

        expect(diff.send(:extract_xml_key_locations, diff_output, '/nonexistent')).to be_empty
      end

      it 'ignores resource-shaped tags inside XML comments' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -1,2 +1,3 @@
           <resources>
          +  <!-- Example: <string name="not_a_resource">Ignored</string> -->
           </resources>
        DIFF

        expect(diff.send(:extract_xml_key_locations, diff_output, '/nonexistent')).to be_empty
      end

      it 'retains the left side and a head fallback for a removed translator comment' do
        diff = described_class.new(base_ref: 'main')
        path = 'res/values/strings.xml'
        base_content = <<~XML
          <resources>
            <!-- Old context -->
            <string name="save_button">Save</string>
          </resources>
        XML
        head_content = <<~XML
          <resources>
            <string name="save_button">Save</string>
          </resources>
        XML
        diff_output = <<~DIFF
          @@ -1,4 +1,3 @@
           <resources>
          -  <!-- Old context -->
             <string name="save_button">Save</string>
           </resources>
        DIFF

        locations = diff.send(
          :extract_xml_key_locations,
          diff_output,
          path,
          base_content: base_content,
          head_content: head_content
        )

        expect(locations.fetch('save_button')).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(
            file: path,
            line: 2,
            side: :left,
            fallback_line: 2
          )
        )
      end
    end

    context 'with orphaned item resolution' do
      it 'resolves orphaned items by reading the actual file' do
        diff = described_class.new(base_ref: 'main')

        # Create a temp file with a large string-array
        Dir.mktmpdir do |dir|
          xml_path = File.join(dir, 'strings.xml')
          items = (0..34).map { |i| "        <item>Item #{i}</item>" }.join("\n")
          File.write(xml_path, <<~XML)
            <resources>
                <string-array name="big_array">
            #{items}
                </string-array>
            </resources>
          XML

          # Simulate a diff where only the last item is changed, and the
          # parent opener is NOT in the hunk context
          diff_output = <<~DIFF
            @@ -34,3 +34,3 @@
                     <item>Item 32</item>
                     <item>Item 33</item>
            -        <item>Item 34</item>
            +        <item>Item 34 CHANGED</item>
                 </string-array>
          DIFF

          keys = diff.send(:extract_xml_key_locations, diff_output, xml_path).keys.to_set

          expect(keys).to include('big_array')
        end
      end

      it 'handles orphaned items when file does not exist' do
        diff = described_class.new(base_ref: 'main')

        diff_output = <<~DIFF
          @@ -34,2 +34,2 @@
          -        <item>Old</item>
          +        <item>New</item>
        DIFF

        # Should not raise, just return what it can
        keys = diff.send(:extract_xml_key_locations, diff_output, '/nonexistent/path.xml').keys.to_set

        expect(keys).to be_a(Set)
      end
    end

    context 'with hunk header parsing' do
      it 'tracks file line numbers correctly across hunks' do
        diff = described_class.new(base_ref: 'main')

        Dir.mktmpdir do |dir|
          xml_path = File.join(dir, 'strings.xml')
          File.write(xml_path, <<~XML)
            <resources>
                <string name="first">First</string>
                <string name="second">Second</string>
                <string-array name="colors">
                    <item>Red</item>
                    <item>Green</item>
                    <item>Blue</item>
                </string-array>
                <string name="last">Last</string>
            </resources>
          XML

          # Two separate hunks
          diff_output = <<~DIFF
            @@ -2,1 +2,1 @@
            -    <string name="first">First</string>
            +    <string name="first">First Updated</string>
            @@ -5,3 +5,3 @@
                     <item>Red</item>
            -        <item>Green</item>
            +        <item>Green Updated</item>
                     <item>Blue</item>
          DIFF

          keys = diff.send(:extract_xml_key_locations, diff_output, xml_path).keys.to_set

          expect(keys).to include('first')
          expect(keys).to include('colors')
        end
      end

      it 'does not leak collection state into a later hunk' do
        diff = described_class.new(base_ref: 'main')
        diff_output = <<~DIFF
          @@ -1,3 +1,4 @@
           <resources>
           <plurals name="old">
          +  <item quantity="one">One</item>
          @@ -10,2 +11,3 @@
          +  <string name="new">New</string>
           </resources>
        DIFF

        locations = diff.send(
          :extract_xml_key_locations,
          diff_output,
          '/nonexistent.xml'
        )

        expect(locations.fetch('old')).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(
            file: '/nonexistent.xml',
            line: 3,
            side: :right
          )
        )
        expect(locations.fetch('new')).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(
            file: '/nonexistent.xml',
            line: 11,
            side: :right
          )
        )
      end
    end
  end

  describe '#resolve_orphaned_items' do
    it 'maps orphaned line numbers to their parent elements' do
      diff = described_class.new(base_ref: 'main')

      Dir.mktmpdir do |dir|
        xml_path = File.join(dir, 'strings.xml')
        File.write(xml_path, <<~XML)
          <resources>
              <plurals name="count">
                  <item quantity="one">%d thing</item>
                  <item quantity="other">%d things</item>
              </plurals>
          </resources>
        XML

        keys = Set.new
        # Line 4 is inside the <plurals name="count"> block
        diff.send(:resolve_orphaned_items, keys, [4], xml_path)

        expect(keys).to include('count')
      end
    end

    it 'does nothing when orphaned_lines is empty' do
      diff = described_class.new(base_ref: 'main')
      keys = Set.new

      # Should not raise
      diff.send(:resolve_orphaned_items, keys, [], '/some/file.xml')

      expect(keys).to be_empty
    end
  end

  describe 'Apple string catalog changes' do
    it 'attributes changed values and comments to their catalog keys' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.xcstrings')
        File.write(path, <<~JSON)
          {
            "sourceLanguage": "en",
            "strings": {
              "settings.title": {
                "comment": "New settings context",
                "localizations": {
                  "en": {
                    "stringUnit": {
                      "state": "translated",
                      "value": "Settings"
                    }
                  }
                }
              },
              "profile.title": {
                "comment": "Profile context"
              }
            },
            "version": "1.0"
          }
        JSON
        diff_output = <<~DIFF
          diff --git a/Localizable.xcstrings b/Localizable.xcstrings
          --- a/Localizable.xcstrings
          +++ b/Localizable.xcstrings
          @@ -3,7 +3,7 @@
             "strings": {
               "settings.title": {
          -      "comment": "Old settings context",
          +      "comment": "New settings context",
                 "localizations": {
                   "en": {
                     "stringUnit": {
          @@ -14,4 +14,5 @@
               },
               "profile.title": {
          +      "comment": "Profile context"
               }
        DIFF

        locations = described_class.new.send(
          :extract_xcstrings_key_locations,
          diff_output,
          path
        )

        expect(locations.keys).to contain_exactly('settings.title', 'profile.title')
        expect(locations['settings.title']).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(file: path, line: 5, side: :right)
        )
        expect(locations['profile.title']).to contain_exactly(
          I18nContextGenerator::ChangedLocation.new(file: path, line: 16, side: :right)
        )
      end
    end

    it 'uses base lines for removals instead of attributing them to the following key' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.xcstrings')
        base_content = <<~JSON
          {
            "sourceLanguage" : "en",
            "strings" : {
              "removed.key" : {
                "comment" : "Remove this entry"
              },
              "remaining.key" : {
                "comment" : "Keep this entry"
              }
            },
            "version" : "1.0"
          }
        JSON
        head_content = <<~JSON
          {
            "sourceLanguage" : "en",
            "strings" : {
              "remaining.key" : {
                "comment" : "Keep this entry"
              }
            },
            "version" : "1.0"
          }
        JSON
        File.write(path, head_content)
        diff_output = <<~DIFF
          @@ -2,9 +2,6 @@
             "sourceLanguage" : "en",
             "strings" : {
          -    "removed.key" : {
          -      "comment" : "Remove this entry"
          -    },
               "remaining.key" : {
                 "comment" : "Keep this entry"
               }
        DIFF

        locations = described_class.new.send(
          :extract_xcstrings_key_locations,
          diff_output,
          path,
          base_content: base_content,
          head_content: head_content
        )

        expect(locations.keys).to contain_exactly('removed.key')
        expect(locations.fetch('removed.key')).to all(
          have_attributes(side: :left, fallback_line: nil)
        )
      end
    end

    it 'uses configured revision content instead of a divergent working tree' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'Localizable.xcstrings')
        revision_content = <<~JSON
          {
            "sourceLanguage" : "en",
            "strings" : {
              "changed.key" : {
                "comment" : "New context"
              }
            },
            "version" : "1.0"
          }
        JSON
        working_content = revision_content.sub(
          '"strings" : {',
          %("strings" : {\n    "working.tree.only" : {},)
        )
        File.write(path, working_content)
        diff_output = <<~DIFF
          @@ -3,5 +3,5 @@
             "strings" : {
               "changed.key" : {
          -      "comment" : "Old context"
          +      "comment" : "New context"
               }
             },
        DIFF

        locations = described_class.new.send(
          :extract_xcstrings_key_locations,
          diff_output,
          path,
          base_content: revision_content.sub('New context', 'Old context'),
          head_content: revision_content
        )

        expect(locations.keys).to contain_exactly('changed.key')
      end
    end

    it 'indexes removals against the merge base when the base branch has advanced' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          system('git', 'init', '-q', '-b', 'main')
          path = 'Localizable.xcstrings'
          catalog = lambda do |keys|
            entries = keys.map { |key| %(    "#{key}" : {}) }.join(",\n")
            <<~JSON
              {
                "sourceLanguage" : "en",
                "strings" : {
              #{entries}
                },
                "version" : "1.0"
              }
            JSON
          end
          commit = lambda do |message|
            system('git', 'add', path)
            system(
              'git',
              '-c', 'user.name=i18n-context-generator',
              '-c', 'user.email=i18n-context-generator@example.com',
              'commit', '-q', '-m', message
            )
          end

          File.write(path, catalog.call(%w[alpha.key beta.key gamma.key]))
          commit.call('Create catalog')
          system('git', 'checkout', '-q', '-b', 'feature')
          File.write(path, catalog.call(%w[beta.key gamma.key]))
          commit.call('Remove alpha')
          system('git', 'checkout', '-q', 'main')
          File.write(path, catalog.call(%w[aaa.newkey alpha.key beta.key gamma.key]))
          commit.call('Advance base catalog')
          system('git', 'checkout', '-q', 'feature')

          locations = described_class.new(
            base_ref: 'main',
            head_ref: 'HEAD'
          ).changed_key_locations([path])

          expect(locations.keys).to contain_exactly([path, 'alpha.key'])
          expect(locations.keys).not_to include([path, 'aaa.newkey'])
        end
      end
    end
  end
end
