# frozen_string_literal: true

# Parses CHANGELOG.md to extract pending changes and guess the next semver bump
class ChangelogParser
  TRUNK = 'Trunk'
  NONE = '_None_'
  SEMVER_WEIGHTS = {
    'Breaking Changes' => 3,
    'New Features' => 2,
    'Bug Fixes' => 1,
    'Internal Changes' => 1
  }.freeze

  attr_reader :latest_version, :pending_lines

  def initialize(file: 'CHANGELOG.md')
    @file = file
    @lines = File.readlines(file)
    parse!
  end

  def guessed_next_version(current:)
    parts = current.split('.')
    bump_at = 3 - semver_weight
    parts[bump_at] = (parts[bump_at].to_i + 1).to_s
    ((bump_at + 1)...parts.length).each { |i| parts[i] = '0' }
    parts.join('.')
  end

  def write_release(new_version:)
    File.open(@file, 'w') do |f|
      @preamble.each { |l| f.print l }
      f.puts empty_trunk
      f.puts
      f.puts "## #{new_version}"
      f.puts
      @pending_lines.each { |l| f.print l }
      @tail.each { |l| f.print l }
    end
  end

  private

  def parse!
    h2_indices = @lines.each_index.select { |i| @lines[i].match?(/^## /) }
    raise "No sections found in #{@file}" if h2_indices.empty?

    trunk_start = h2_indices[0]
    trunk_title = @lines[trunk_start].match(/^## (.+)/)[1].strip
    raise "Expected '#{TRUNK}' as first section, found '#{trunk_title}'" unless trunk_title == TRUNK

    next_h2 = h2_indices[1] || @lines.length

    @preamble = @lines[0...trunk_start]
    @pending_lines = extract_pending(@lines[(trunk_start + 1)...next_h2])
    version_match = @lines[next_h2]&.match(/^## (.+)/)
    @latest_version = version_match && version_match[1].strip
    @tail = @lines[next_h2..] || []
  end

  # Groups lines by ### subsections, keeps only those with real content
  def extract_pending(lines)
    chunks = chunk_by_subsection(lines)
    chunks
      .select { |_, body| body.any? { |l| !l.strip.empty? && l.strip != NONE } }
      .flat_map { |header, body| [header] + body }
  end

  def chunk_by_subsection(lines)
    chunks = []
    header = nil
    body = []

    lines.each do |line|
      if line.match?(/^### /)
        chunks << [header, body] if header
        header = line
        body = []
      else
        body << line
      end
    end
    chunks << [header, body] if header
    chunks
  end

  def semver_weight
    @pending_lines
      .filter_map { |l| (m = l.match(/^### (.+)/)) && SEMVER_WEIGHTS[m[1].strip] }
      .max || 1
  end

  def empty_trunk
    subsections = SEMVER_WEIGHTS.keys.map { |name| "### #{name}\n\n#{NONE}\n" }
    "## #{TRUNK}\n\n#{subsections.join("\n")}"
  end
end
