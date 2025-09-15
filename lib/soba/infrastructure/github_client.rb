# frozen_string_literal: true

module Soba
  module Infrastructure
    class GitHubClient
      def initialize(token: ENV["GITHUB_TOKEN"])
        @octokit = Octokit::Client.new(access_token: token)
      end

      def issues(repository, state: "open")
        @octokit.issues(repository, state: state)
      end

      def issue(repository, number)
        @octokit.issue(repository, number)
      end
    end
  end
end