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

      def update_issue_labels_with_check(repository, issue_number, from:, to:)
        logger.info "Atomic label update with check",
                    repository: repository,
                    issue: issue_number,
                    from: from,
                    to: to

        with_error_handling do
          with_rate_limit_check do
            # Get current labels to check state
            issue = @octokit.issue(repository, issue_number)
            current_labels = issue.labels.map(&:name)

            # Check if the issue has the expected 'from' label
            unless current_labels.include?(from)
              logger.warn "Label state mismatch: expected '#{from}' not found",
                          repository: repository,
                          issue: issue_number,
                          current_labels: current_labels
              return false
            end

            # Check if the issue already has the 'to' label (duplicate transition)
            if current_labels.include?(to)
              logger.warn "Duplicate transition detected: '#{to}' already exists",
                          repository: repository,
                          issue: issue_number,
                          current_labels: current_labels
              return false
            end

            # Perform the label update atomically
            new_labels = current_labels - [from]
            new_labels << to

            @octokit.replace_all_labels(repository, issue_number, new_labels)

            logger.info "Labels updated atomically",
                        repository: repository,
                        issue: issue_number,
                        updated_labels: new_labels
            true
          end
        end
      rescue => e
        logger.error "Failed to update labels atomically",
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

      def list_labels(repository)
        logger.info "Fetching labels", repository: repository

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.labels(repository)
          end
        end

        response.map do |label|
          {
            name: label.name,
            color: label.color,
            description: label.description,
          }
        end
      rescue => e
        logger.error "Failed to fetch labels", error: e.message, repository: repository
        raise
      end

      def create_label(repository, name, color, description)
        logger.info "Creating label", repository: repository, name: name, color: color

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.add_label(repository, name, color, description: description)
          end
        end

        {
          name: response.name,
          color: response.color,
          description: response.description,
        }
      rescue Octokit::UnprocessableEntity
        # Check if error is because label already exists
        # Octokit will return "Validation failed" as the message
        logger.info "Label already exists, skipping", repository: repository, name: name
        nil
      rescue => e
        logger.error "Failed to create label", error: e.message, repository: repository, name: name
        raise
      end

      def search_pull_requests(repository:, labels: [])
        logger.info "Searching pull requests", repository: repository, labels: labels

        query_parts = ["type:pr", "is:open", "repo:#{repository}"]
        query_parts += labels.map { |label| "label:#{label}" }
        query = query_parts.join(" ")

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.search_issues(query)
          end
        end

        response.items.map do |pr|
          {
            number: pr.number,
            title: pr.title,
            state: pr.state,
            labels: pr.labels.map { |l| { name: l.name } },
          }
        end
      rescue => e
        logger.error "Failed to search pull requests", error: e.message, repository: repository
        raise
      end

      def merge_pull_request(repository, pr_number, merge_method: "squash")
        logger.info "Merging pull request", repository: repository, pr_number: pr_number, merge_method: merge_method

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.merge_pull_request(repository, pr_number, "", merge_method: merge_method)
          end
        end

        {
          sha: response.sha,
          merged: response.merged,
          message: response.message,
        }
      rescue Octokit::MethodNotAllowed => e
        logger.error "Pull request not mergeable", repository: repository, pr_number: pr_number, error: e.message
        raise MergeConflictError, "Pull request is not mergeable: #{e.message}"
      rescue => e
        logger.error "Failed to merge pull request", error: e.message, repository: repository, pr_number: pr_number
        raise
      end

      def get_pull_request(repository, pr_number)
        logger.info "Fetching pull request", repository: repository, pr_number: pr_number

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.pull_request(repository, pr_number)
          end
        end

        {
          number: response.number,
          title: response.title,
          body: response.body,
          state: response.state,
          mergeable: response.mergeable,
          mergeable_state: response.mergeable_state,
        }
      rescue => e
        logger.error "Failed to fetch pull request", error: e.message, repository: repository, pr_number: pr_number
        raise
      end

      def get_pr_issue_number(repository, pr_number)
        logger.info "Extracting issue number from PR", repository: repository, pr_number: pr_number

        pr = get_pull_request(repository, pr_number)
        body = pr[:body] || ""

        # Match patterns like: fixes #123, closes #456, resolves #789
        match = body.match(/(?:fixes|closes|resolves|fix|close|resolve)\s+#(\d+)/i)
        return match[1].to_i if match

        nil
      rescue => e
        logger.error "Failed to extract issue number", error: e.message, repository: repository, pr_number: pr_number
        nil
      end

      def close_issue_with_label(repository, issue_number, label:)
        logger.info "Closing issue with label", repository: repository, issue_number: issue_number, label: label

        with_error_handling do
          with_rate_limit_check do
            # Close the issue
            @octokit.close_issue(repository, issue_number)

            # Add label
            @octokit.add_labels_to_an_issue(repository, issue_number, [label])
          end
        end

        logger.info "Issue closed and labeled successfully", repository: repository, issue_number: issue_number
        true
      rescue => e
        logger.error "Failed to close issue with label", error: e.message, repository: repository,
                                                         issue_number: issue_number
        raise
      end

      def fetch_closed_issues(repository)
        logger.info "Fetching closed issues", repository: repository

        response = with_error_handling do
          with_rate_limit_check do
            @octokit.issues(repository, state: "closed")
          end
        end

        map_issues_to_domain(response)
      rescue => e
        logger.error "Failed to fetch closed issues", error: e.message, repository: repository
        raise
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