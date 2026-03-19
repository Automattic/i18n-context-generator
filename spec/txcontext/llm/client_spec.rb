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

      def http_client_for(uri:, **kwargs)
        send(:http_for, uri, **kwargs)
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

  it 'redacts the original translation text when prompt redaction is enabled' do
    prompt = client.prompt_for(
      key: 'support.email',
      text: 'Contact mobile@example.com for support',
      matches: [match]
    )

    expect(prompt).to include('[REDACTED_EMAIL]')
    expect(prompt).not_to include('Contact mobile@example.com for support')
  end

  it 'instructs the model not to speculate or infer max length' do
    prompt = client.prompt_for(
      key: 'settings.title',
      text: 'Settings',
      matches: [match]
    )

    expect(prompt).to include('Never use words like "likely", "probably", "appears", "seems", "may", or "might"')
    expect(prompt).to include('Only set `max_length` when there is explicit evidence for a concrete numeric limit; otherwise return null')
    expect(prompt).to include('keep the description generic rather than inventing a specific screen, flow, or user action')
  end

  describe '.for' do
    it 'builds an Anthropic client' do
      anthropic_client = instance_double(Txcontext::LLM::Anthropic)
      allow(Txcontext::LLM::Anthropic).to receive(:new).and_return(anthropic_client)

      expect(described_class.for('anthropic')).to eq(anthropic_client)
    end

    it 'builds an Anthropic client from a symbol provider' do
      anthropic_client = instance_double(Txcontext::LLM::Anthropic)
      allow(Txcontext::LLM::Anthropic).to receive(:new).and_return(anthropic_client)

      expect(described_class.for(:anthropic)).to eq(anthropic_client)
    end

    it 'builds an OpenAI client' do
      openai_client = instance_double(Txcontext::LLM::OpenAI)
      allow(Txcontext::LLM::OpenAI).to receive(:new).and_return(openai_client)

      expect(described_class.for('openai')).to eq(openai_client)
    end
  end

  it 'parses markdown-wrapped JSON responses' do
    result = client.send(
      :parse_response,
      <<~TEXT
        ```json
        {"description":"Primary save action","ui_element":"button","tone":"neutral","max_length":12}
        ```
      TEXT
    )

    expect(result.description).to eq('Primary save action')
    expect(result.ui_element).to eq('button')
    expect(result.tone).to eq('neutral')
    expect(result.max_length).to eq(12)
    expect(result.error).to be_nil
  end

  it 'redacts 32-character hex tokens without redacting UUIDs' do
    text = [
      'checksum=0123456789abcdef0123456789abcdef',
      'id=123e4567-e89b-12d3-a456-426614174000'
    ].join("\n")

    sanitized = client.send(:sanitize_prompt_text, text, redact: true)

    expect(sanitized).to include('checksum=[REDACTED_TOKEN]')
    expect(sanitized).to include('id=123e4567-e89b-12d3-a456-426614174000')
  end

  it 'reuses HTTP sessions within a thread while isolating them across threads' do
    fake_http_class = Class.new do
      attr_accessor :use_ssl, :open_timeout, :read_timeout, :keep_alive_timeout

      def initialize(_host, _port)
        @started = false
      end

      def start
        @started = true
        self
      end

      def started?
        @started
      end
    end

    allow(Net::HTTP).to receive(:new) { |host, port| fake_http_class.new(host, port) }

    uri = URI('https://api.example.test/v1/responses')

    main_thread_http = client.http_client_for(uri: uri, open_timeout: 10, read_timeout: 60)
    same_thread_http = client.http_client_for(uri: uri, open_timeout: 10, read_timeout: 30)

    thread_http = nil
    thread_http_again = nil
    Thread.new do
      thread_http = client.http_client_for(uri: uri, open_timeout: 10, read_timeout: 60)
      thread_http_again = client.http_client_for(uri: uri, open_timeout: 10, read_timeout: 15)
    end.join

    expect(same_thread_http).to be(main_thread_http)
    expect(main_thread_http.read_timeout).to eq(30)
    expect(thread_http_again).to be(thread_http)
    expect(thread_http).not_to be(main_thread_http)
    expect(thread_http.read_timeout).to eq(15)
    expect(Net::HTTP).to have_received(:new).twice
  end
end
