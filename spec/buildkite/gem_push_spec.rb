# frozen_string_literal: true

require 'open3'

# rubocop:disable RSpec/DescribeClass -- integration test for the publish script
RSpec.describe 'RubyGems publish script' do
  it 'uses a private temporary credential file and removes it after publishing' do
    Dir.mktmpdir do |dir|
      bin_dir = File.join(dir, 'bin')
      capture_path = File.join(dir, 'credential-path')
      FileUtils.mkdir_p(bin_dir)
      fake_gem = File.join(bin_dir, 'gem')
      File.write(fake_gem, <<~SH)
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--config-file" ]; then
            shift
            test -f "$1" || exit 10
            grep -q "$EXPECTED_CREDENTIAL" "$1" || exit 11
            printf '%s' "$1" > "$CAPTURE_PATH"
          fi
          shift
        done
      SH
      File.chmod(0o755, fake_gem)

      secret = 'temporary-test-api-key'
      script = File.expand_path('../../.buildkite/gem-push.sh', __dir__)
      stdout, stderr, status = Open3.capture3(
        {
          'PATH' => "#{bin_dir}:#{ENV.fetch('PATH')}",
          'TMPDIR' => dir,
          'RUBYGEMS_API_KEY' => secret,
          'EXPECTED_CREDENTIAL' => secret,
          'CAPTURE_PATH' => capture_path
        },
        script,
        chdir: dir
      )

      expect(status).to be_success, stderr
      credential_path = File.read(capture_path)
      expect(File.dirname(credential_path)).to eq(dir)
      expect(File.exist?(credential_path)).to be(false)
      expect(stdout).not_to include(secret)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
