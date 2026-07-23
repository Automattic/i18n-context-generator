# frozen_string_literal: true

require_relative '../android_resource'
require_relative '../translation_comment_index'
require_relative '../xml_scanner'

module I18nContextGenerator
  # Android XML diff parsing kept separate from Git command/path orchestration.
  module GitDiffXmlChanges
    private

    def extract_xml_keys(diff_output, file_path, base_content: nil, head_content: nil)
      extract_xml_changes(
        diff_output,
        file_path,
        base_content: base_content,
        head_content: head_content
      )[:keys]
    end

    def extract_xml_key_locations(diff_output, file_path, base_content: nil, head_content: nil)
      extract_xml_changes(
        diff_output,
        file_path,
        base_content: base_content,
        head_content: head_content
      )[:locations]
    end

    def extract_xml_changes(diff_output, file_path, base_content: nil, head_content: nil)
      state = initial_xml_diff_state(file_path)
      parse_xml_diff!(state, diff_output)
      resolve_orphaned_items(
        state[:keys],
        state[:orphaned_item_file_lines],
        file_path,
        locations: state[:locations],
        content: head_content
      )
      add_comment_only_locations(
        state[:locations],
        state[:added_file_lines],
        file_path,
        format: :xml,
        content: head_content
      ) { |line_number| line_number }

      typed_locations = state[:locations].transform_values do |lines|
        lines.map { |line| changed_location(file_path, line, side: :right) }
      end
      merge_removed_xml_locations!(
        typed_locations,
        diff_output,
        file_path,
        base_content: base_content,
        head_content: head_content
      )
      typed_locations = prefer_right_locations(typed_locations)
      state[:keys].merge(typed_locations.keys)

      { keys: state[:keys], locations: typed_locations }
    end

    def initial_xml_diff_state(file_path)
      {
        keys: Set.new,
        locations: Hash.new { |hash, key| hash[key] = Set.new },
        current_parent: nil,
        current_string: nil,
        file_line: nil,
        orphaned_item_file_lines: [],
        pending_tag: nil,
        file_path: file_path,
        added_file_lines: [],
        xml_comment_state: {}
      }
    end

    def parse_xml_diff!(state, diff_output)
      diff_output.each_line do |line|
        next if update_xml_hunk_line?(state, line)
        next if line.start_with?('diff ', 'index ', '--- ', '+++ ')

        is_removed = line.start_with?('-')
        is_added = line.start_with?('+')
        content = line.sub(/^[ +-]/, '')
        process_xml_diff_line(state, content, added: is_added) unless is_removed
        state[:file_line] += 1 if state[:file_line] && !is_removed
      end
    end

    def process_xml_diff_line(state, content, added:)
      state[:added_file_lines] << state[:file_line] if added && state[:file_line]
      visible_content, contained_comment = XmlScanner.without_comments(
        content,
        state[:xml_comment_state]
      )
      process_xml_diff_content(
        state,
        visible_content,
        added: added,
        contained_comment: contained_comment
      )
    end

    def update_xml_hunk_line?(state, line)
      hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
      return false unless hunk

      state[:file_line] = hunk[1].to_i
      state[:current_parent] = nil
      state[:current_string] = nil
      state[:pending_tag] = nil
      state[:xml_comment_state] = {}
      true
    end

    def process_xml_diff_content(state, content, added:, contained_comment: false)
      meaningful_change = !content.strip.empty? || contained_comment
      record_xml_change(state, state[:current_parent]) if added && meaningful_change && state[:current_parent]
      record_xml_change(state, state[:current_string]) if added && meaningful_change && state[:current_string]

      accumulate_xml_opening_tag(state, content, added: added)
      complete_xml_opening_tag(state) if state.dig(:pending_tag, :content)&.include?('>')
      track_xml_item_change(state) if added && content.match?(/<item\b/)

      state[:current_string] = nil if content.match?(%r{</string>})
      state[:current_parent] = nil if content.match?(%r{</(?:plurals|string-array)>})
    end

    def accumulate_xml_opening_tag(state, content, added:)
      if state[:pending_tag]
        state[:pending_tag][:content] << content
        state[:pending_tag][:added] ||= added
        state[:pending_tag][:first_added_line] ||= state[:file_line] if added
      elsif (tag_start = content.index(/<(?:string-array|plurals|string)\b/))
        state[:pending_tag] = {
          content: content[tag_start..],
          added: added,
          first_added_line: (state[:file_line] if added)
        }
      end
    end

    def complete_xml_opening_tag(state)
      tag = state[:pending_tag]
      resource = resource_from_opening_tag(tag[:content])
      if resource
        record_xml_change(state, resource[:name], line: tag[:first_added_line]) if tag[:added]
        track_open_xml_resource(state, resource, tag[:content])
      end
      state[:pending_tag] = nil
    end

    def track_open_xml_resource(state, resource, content)
      if resource[:type] == :string
        state[:current_string] = resource[:name] unless content.include?('</string>')
      elsif !content.include?("</#{AndroidResource.tag_for_type(resource[:type])}>")
        state[:current_parent] = resource[:name]
      end
    end

    def track_xml_item_change(state)
      if state[:current_parent]
        record_xml_change(state, state[:current_parent])
      elsif state[:file_line]
        state[:orphaned_item_file_lines] << state[:file_line]
      end
    end

    def record_xml_change(state, key, line: state[:file_line])
      return unless key

      state[:keys] << key
      state[:locations][key] << line if line
    end

    def resource_from_opening_tag(tag)
      type_match = tag.match(/<(string-array|plurals|string)\b/)
      name_match = tag.match(/\bname\s*=\s*(["'])(.*?)\1/m)
      return unless type_match && name_match

      { type: AndroidResource.type_for_tag(type_match[1]), name: name_match[2] }
    end

    def resolve_orphaned_items(keys, orphaned_lines, file_path, locations: nil, content: nil)
      return if orphaned_lines.empty?
      return if content.nil? && !File.exist?(file_path)

      resource_index = AndroidResource.index(content || File.read(file_path, encoding: 'UTF-8'))

      orphaned_lines.each do |line_num|
        parent = resource_index.base_key_at(line_num)
        next unless parent

        keys << parent
        locations[parent] << line_num if locations
      end
    end

    def add_comment_only_locations(locations, added_lines, file_path, format:, content: nil)
      return if content.nil? && !File.file?(file_path)

      comment_index = TranslationCommentIndex.new(file_path, format: format, content: content)

      added_lines.each do |line_number|
        key = comment_index.key_at(line_number)
        next unless key
        next if locations[key].any?

        locations[key] << yield(line_number)
      end
    end

    def merge_removed_xml_locations!(locations, diff_output, file_path, base_content:, head_content:)
      return unless base_content && head_content

      base_comments = TranslationCommentIndex.new(format: :xml, content: base_content)
      head_comments = TranslationCommentIndex.new(format: :xml, content: head_content)
      base_resources = AndroidResource.index(base_content)
      head_resources = AndroidResource.index(head_content)

      each_changed_diff_line(diff_output) do |content, old_line, _new_line, side|
        next unless side == :left
        next if content.strip.empty?

        key = base_comments.key_at(old_line) || base_resources.base_key_at(old_line)
        next unless key

        fallback_line = head_comments.line_for_key(key) || resource_start_line(head_resources, key)
        (locations[key] ||= []) << changed_location(
          file_path,
          old_line,
          side: :left,
          fallback_line: fallback_line
        )
      end
    end

    def resource_start_line(index, key)
      index.resource_spans.find { |span| span.base_key == key }&.start_line
    end
  end
end
