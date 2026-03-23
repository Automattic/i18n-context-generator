# frozen_string_literal: true

# Colored terminal output helpers for interactive rake tasks
module Console
  RED = 1
  GREEN = 2
  YELLOW = 3

  def self.color_puts(text, color_code:)
    puts "\x1b[3#{color_code}m#{text}\x1b[0m"
  end

  def self.header(text)
    color_puts(">>> #{text}", color_code: GREEN)
  end

  def self.info(text)
    color_puts(text, color_code: YELLOW)
  end

  def self.warning(text)
    color_puts(text, color_code: RED)
  end

  def self.print_indented_lines(lines)
    color_puts(lines.map { |l| "| #{l}" }.join, color_code: YELLOW)
  end

  def self.prompt(text, default_value)
    color_puts("#{text}? [default: #{default_value}] ", color_code: GREEN)
    answer = $stdin.gets.chomp
    answer.empty? ? default_value : answer
  end

  def self.confirm?(text)
    color_puts("#{text} [y/n]?", color_code: GREEN)
    $stdin.gets.chomp.casecmp('y').zero?
  end
end
