# frozen_string_literal: true

module Soba
  module Infrastructure
    class GitHubClientError < StandardError; end

    class AuthenticationError < GitHubClientError; end

    class RateLimitExceeded < GitHubClientError; end

    class NetworkError < GitHubClientError; end
  end
end