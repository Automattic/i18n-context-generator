# frozen_string_literal: true

RSpec.describe Txcontext::LLM::Client do
  let(:client_class) do
    Class.new(described_class) do
      def generate_context(**_kwargs)
        raise NotImplementedError
      end

      def prompt_for(**kwargs)
        send(:build_prompt, **kwargs)
      end
    end
  end
  let(:client) { client_class.new }
  let(:match) do
    Txcontext::Searcher::Match.new(
      file: '/Users/ian/dev/txcontext/app/screens/SettingsViewController.swift',
      line: 42,
      match_line: 'let title = NSLocalizedString("settings.title", comment: "")',
      context: <<~CONTEXT.chomp,
        let supportEmail = "mobile@example.com"
        let apiKey = "super-secret-value"
        >>> let title = NSLocalizedString("settings.title", comment: "")
        let docsUrl = "https://internal.example.com/settings"
      CONTEXT
      enclosing_scope: 'func render'
    )
  end

  it 'redacts likely secrets and hides full file paths by default' do
    prompt = client.prompt_for(
      key: 'settings.title',
      text: 'Settings',
      matches: [match],
      comment: 'Contact mobile@example.com for rollout status'
    )

    expect(prompt).to include('SettingsViewController.swift:42')
    expect(prompt).not_to include('/Users/ian/dev/txcontext')
    expect(prompt).to include('[REDACTED_EMAIL]')
    expect(prompt).to include('[REDACTED_SECRET]')
    expect(prompt).to include('[REDACTED_URL]')
    expect(prompt).not_to include('super-secret-value')
  end

  it 'can include full file paths and raw prompt content when requested' do
    prompt = client.prompt_for(
      key: 'settings.title',
      text: 'Settings',
      matches: [match],
      comment: 'Contact mobile@example.com for rollout status',
      include_file_paths: true,
      redact_prompts: false
    )

    expect(prompt).to include('/Users/ian/dev/txcontext/app/screens/SettingsViewController.swift:42')
    expect(prompt).to include('mobile@example.com')
    expect(prompt).to include('super-secret-value')
    expect(prompt).to include('https://internal.example.com/settings')
  end
end
