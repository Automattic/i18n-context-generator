# frozen_string_literal: true

require "json"
require "yaml"
require "csv"
require "digest"
require "fileutils"
require "shellwords"

require "oj"
require "httpx"
require "concurrent"
require "tty-progressbar"
require "dotstrings"

require_relative "txcontext/version"
require_relative "txcontext/config"
require_relative "txcontext/parsers/base"
require_relative "txcontext/parsers/json_parser"
require_relative "txcontext/parsers/yaml_parser"
require_relative "txcontext/parsers/strings_parser"
require_relative "txcontext/parsers/android_xml_parser"
require_relative "txcontext/searcher"
require_relative "txcontext/llm/client"
require_relative "txcontext/llm/anthropic"
require_relative "txcontext/writers/csv_writer"
require_relative "txcontext/writers/json_writer"
require_relative "txcontext/writers/strings_writer"
require_relative "txcontext/writers/android_xml_writer"
require_relative "txcontext/writers/swift_writer"
require_relative "txcontext/cache"
require_relative "txcontext/git_diff"
require_relative "txcontext/context_extractor"

module Txcontext
  class Error < StandardError; end
end
