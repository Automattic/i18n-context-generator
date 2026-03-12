# frozen_string_literal: true

RSpec.describe Txcontext::GitDiff do
  describe '#changed_keys' do
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

        keys = diff.send(:extract_strings_keys, diff_output)

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

        keys = diff.send(:extract_strings_keys, diff_output)

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

        keys = diff.send(:extract_strings_keys, diff_output)

        expect(keys).to include('real.key')
        expect(keys.size).to eq(1)
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

        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent')

        expect(keys).to include('new_key')
        expect(keys).to include('another_key')
        expect(keys).not_to include('existing')
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

        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent')

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

        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent')

        expect(keys).to include('post_likes')
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

        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent')

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

        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent')

        expect(keys).to include('standalone')
        expect(keys).not_to include('old_plural')
      end
    end

    context 'orphaned item resolution' do
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

          keys = diff.send(:extract_xml_keys, diff_output, xml_path)

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
        keys = diff.send(:extract_xml_keys, diff_output, '/nonexistent/path.xml')

        expect(keys).to be_a(Set)
      end
    end

    context 'hunk header parsing' do
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

          keys = diff.send(:extract_xml_keys, diff_output, xml_path)

          expect(keys).to include('first')
          expect(keys).to include('colors')
        end
      end
    end
  end

  describe '#extract_keys_from_diff' do
    it 'routes .strings files to extract_strings_keys' do
      diff = described_class.new(base_ref: 'main')

      diff_output = "+\"some.key\" = \"value\";\n"
      keys = diff.send(:extract_keys_from_diff, diff_output, 'Localizable.strings')

      expect(keys).to include('some.key')
    end

    it 'routes .xml files to extract_xml_keys' do
      diff = described_class.new(base_ref: 'main')

      diff_output = <<~DIFF
        @@ -1,2 +1,3 @@
        +    <string name="xml_key">value</string>
      DIFF

      keys = diff.send(:extract_keys_from_diff, diff_output, 'res/values/strings.xml')

      expect(keys).to include('xml_key')
    end

    it 'returns empty set for unsupported extensions' do
      diff = described_class.new(base_ref: 'main')

      keys = diff.send(:extract_keys_from_diff, 'some diff', 'file.json')

      expect(keys).to be_empty
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
end
