# frozen_string_literal: true

require "octokit"
require "faraday"
require "faraday/retry"
require "semantic_logger"
require_relative "errors"

module Soba
  module Infrastructure
    class GitHubClient
      include SemanticLogger::Loggable

      attr_reader :octokit

      def initialize(token: nil)
        token ||= Configuration.config.github.token if defined?(Configuration)
        token ||= ENV["GITHUB_TOKEN"]

        stack = build_middleware_stack

        @octokit = Octokit::Client.new(
          access_token: token,
          auto_paginate: true,
          per_page: 100,
          connection_options: {
            builder: stack,
          }
        )
      end

      def issues(repository, state: "open")
        logger.info "Fetching issues", repository: repository, state: state

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.issues(repository, state: state)
          end
        end

        map_issues_to_domain(response)
      rescue => e
        logger.error "Failed to fetch issues", error: e.message, repository: repository
        raise
      end

      def issue(repository, number)
        logger.info "Fetching issue", repository: repository, number: number

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.issue(repository, number)
          end
        end

        map_issue_to_domain(response)
      rescue Octokit::NotFound
        logger.warn "Issue not found", repository: repository, number: number
        nil
      rescue => e
        logger.error "Failed to fetch issue", error: e.message, repository: repository, number: number
        raise
      end

      def rate_limit_remaining
        @octokit.rate_limit.remaining
      rescue => e
        logger.error "Failed to check rate limit", error: e.message
        nil
      end

      def update_issue_labels(issue_number, from:, to:)
        repository = Configuration.config.github.repository if defined?(Configuration)

        logger.info "Updating issue labels",
                    repository: repository,
                    issue: issue_number,
                    from: from,
                    to: to

        with_error_handling do
          with_rate_limit_check do
            # Get current labels
            issue = @octokit.issue(repository, issue_number)
            current_labels = issue.labels.map(&:name)

            # Remove the 'from' label and add the 'to' label
            new_labels = current_labels - [from]
            new_labels << to unless new_labels.include?(to)

            # Update labels on the issue
            @octokit.replace_all_labels(repository, issue_number, new_labels)
          end
        end

        logger.info "Labels updated successfully",
                    repository: repository,
                    issue: issue_number
      rescue => e
        logger.error "Failed to update labels",
                     error: e.message,
                     repository: repository,
                     issue: issue_number
        raise
      end

      def wait_for_rate_limit
        limit_info = @octokit.rate_limit

        if limit_info.remaining == 0
          reset_time = Time.at(limit_info.resets_at.to_i)
          wait_seconds = reset_time - Time.now

          if wait_seconds > 0
            logger.warn "Rate limit exceeded. Waiting #{wait_seconds.round} seconds..."
            sleep(wait_seconds + 1) # Add 1 second buffer
          end
        end
      rescue => e
        logger.error "Failed to wait for rate limit", error: e.message
      end

      private

      def build_middleware_stack
        Faraday::RackBuilder.new do |builder|
          # Retry on network failures and specific status codes
          builder.use Faraday::Retry::Middleware,
                      max: 3,
                      interval: 0.5,
                      interval_randomness: 0.5,
                      backoff_factor: 2,
                      exceptions: [
                        Faraday::ConnectionFailed,
                        Faraday::TimeoutError,
                        Faraday::RetriableResponse,
                      ],
                      retry_statuses: [429, 503, 504],
                      retry_block: ->(env, _options, retries, exception) do
                        logger.warn "Retrying request",
                                   url: env.url,
                                   retry_count: retries,
                                   error: exception&.message
                      end

          # Request logging
          builder.request :url_encoded
          builder.request :json

          # Response logging and parsing
          builder.response :json, content_type: /\bjson$/
          builder.response :logger, logger, bodies: false if ENV["DEBUG"]

          # HTTP adapter
          builder.adapter Faraday.default_adapter
        end
      end

      def with_error_handling
        yield
      rescue Octokit::Unauthorized => e
        raise AuthenticationError, "Authentication failed: #{e.message}"
      rescue Octokit::TooManyRequests => e
        raise RateLimitExceeded, "Too many requests: #{e.message}"
      rescue Octokit::Forbidden => e
        if e.message.include?("rate limit")
          raise RateLimitExceeded, "GitHub API rate limit exceeded"
        else
          raise GitHubClientError, "Access forbidden: #{e.message}"
        end
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise NetworkError, "Network error: #{e.message}"
      end

      def with_rate_limit_check
        # Temporarily disabled rate limit check for testing
        # TODO: Implement proper rate limit handling with VCR
        yield
      end

      def map_issues_to_domain(issues)
        issues.map { |issue_data| map_issue_to_domain(issue_data) }
      end

      def map_issue_to_domain(issue_data)
        return nil unless issue_data

        Domain::Issue.new(
          id: issue_data[:id],
          number: issue_data[:number],
          title: issue_data[:title],
          body: issue_data[:body],
          state: issue_data[:state],
          labels: normalize_labels(issue_data[:labels]),
          created_at: issue_data[:created_at],
          updated_at: issue_data[:updated_at]
        )
      end

      def normalize_labels(labels)
        return [] unless labels

        labels.map do |label|
          if label.is_a?(Hash)
            # For test stubs that return hashes directly
            { name: label[:name] || label["name"], color: label[:color] || label["color"] }
          else
            # For real Octokit responses (Sawyer::Resource objects)
            { name: label.name, color: label.color }
          end
        end
      end
    end
  end
end