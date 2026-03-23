# frozen_string_literal: true

require 'git'
require 'uri'

# Git operations for the release workflow, backed by the ruby-git gem
module GitHelper
  GITHUB_REPO = 'Automattic/i18n-context-generator'

  def self.repo
    @repo ||= Git.open('.')
  end

  def self.checkout_release_branch(version)
    branch = "release/#{version}"
    current = repo.current_branch

    if current == branch
      Console.info "Already on #{branch}"
    elsif repo.branches[branch]
      repo.checkout(branch)
    else
      abort('Aborted: must run from trunk or an existing release branch') unless current == 'trunk' || Console.confirm?("Not on 'trunk'. Cut release from '#{current}'?")
      repo.branch(branch).checkout
    end
  end

  def self.commit_and_push(message, files)
    repo.add(files)
    repo.commit(message)
    repo.push('origin', repo.current_branch)
  end

  def self.open_pr(version, changelog_text)
    query = URI.encode_www_form(
      expand: 1,
      title: "Release #{version} into trunk",
      body: pr_body(version, changelog_text)
    )
    system('open', "https://github.com/#{GITHUB_REPO}/compare/trunk...release/#{version}?#{query}")
  end

  def self.pr_body(version, changelog_text)
    <<~BODY
      Releasing new version #{version}.

      # What's Next

      Create and publish a GitHub Release pointing to `trunk` once this PR is merged,
      using the changelog below as the release description:
      ```
      #{changelog_text}
      ```
    BODY
  end

  private_class_method :pr_body
end
