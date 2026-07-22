# frozen_string_literal: true

require 'tempfile'
require 'fileutils'

module I18nContextGenerator
  module Writers
    # Safely replaces an existing file after optionally validating the candidate.
    class AtomicFile
      class << self
        def replace(path, content)
          original_mode = File.stat(path).mode & 0o7777
          directory = File.dirname(File.expand_path(path))
          basename = File.basename(path)
          temporary_file = Tempfile.new([".#{basename}.", '.tmp'], directory)
          temporary_path = temporary_file.path

          begin
            temporary_file.binmode
            temporary_file.write(content)
            temporary_file.flush
            temporary_file.fsync
            temporary_file.chmod(original_mode)
            temporary_file.close

            yield temporary_path if block_given?

            File.rename(temporary_path, path)
          ensure
            temporary_file.close unless temporary_file.closed?
            FileUtils.rm_f(temporary_path)
          end
        end
      end
    end
  end
end
