# frozen_string_literal: true

module Soba
  module Infrastructure
    class GitHubClientError < StandardError; end

    class AuthenticationError < GitHubClientError; end

    class RateLimitExceeded < GitHubClientError; end

    class NetworkError < GitHubClientError; end

    class MergeConflictError < GitHubClientError; end

    class TmuxError < StandardError; end

    class TmuxSessionNotFound < TmuxError; end

    class TmuxCommandFailed < TmuxError; end

    class TmuxNotInstalled < TmuxError; end
  end
end