# frozen_string_literal: true

module Txcontext
  module Writers
    # Shared utilities for writer classes (description filtering, file discovery).
    module Helpers
      def skip_description?(description)
        description.include?('No usage found') || description.include?('Processing failed')
      end

      def find_swift_files(path)
        if File.file?(path) && path.end_with?('.swift')
          [path]
        elsif File.directory?(path)
          Dir.glob(File.join(path, '**', '*.swift'))
        else
          []
        end
      end
    end
  end
end
