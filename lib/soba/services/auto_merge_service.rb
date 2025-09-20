# frozen_string_literal: true

require "semantic_logger"
require_relative "../infrastructure/github_client"
require_relative "../configuration"
require_relative "slack_notifier"

module Soba
  module Services
    class AutoMergeService
      include SemanticLogger::Loggable

      def initialize
        @github_client = Infrastructure::GitHubClient.new
        @repository = Configuration.config.github.repository
      end

      def execute
        logger.info "Starting auto-merge process", repository: @repository

        approved_prs = find_approved_prs

        if approved_prs.empty?
          logger.info "No PRs with soba:lgtm label found"
          return {
            merged_count: 0,
            failed_count: 0,
            details: { merged: [], failed: [] },
          }
        end

        logger.info "Found approved PRs", count: approved_prs.size, pr_numbers: approved_prs.map { |pr| pr[:number] }

        merged = []
        failed = []

        approved_prs.each do |pr|
          pr_number = pr[:number]
          logger.info "Processing PR", pr_number: pr_number, title: pr[:title]

          begin
            if check_mergeable(pr_number)
              result = perform_merge(pr_number)
              if result[:merged]
                handle_post_merge(pr_number, sha: result[:sha])
                merged << { number: pr_number, title: pr[:title], sha: result[:sha] }
                logger.info "PR merged successfully", pr_number: pr_number, sha: result[:sha]
              else
                failed << { number: pr_number, title: pr[:title], reason: "Merge returned false" }
                logger.warn "PR merge returned false", pr_number: pr_number
              end
            else
              failed << { number: pr_number, title: pr[:title], reason: "PR is not mergeable (conflicts or CI issues)" }
              logger.warn "PR is not mergeable", pr_number: pr_number
            end
          rescue Infrastructure::MergeConflictError => e
            failed << { number: pr_number, title: pr[:title], reason: e.message }
            logger.error "Merge conflict error", pr_number: pr_number, error: e.message
          rescue => e
            failed << { number: pr_number, title: pr[:title], reason: e.message }
            logger.error "Unexpected error during merge", pr_number: pr_number, error: e.message,
                                                          backtrace: e.backtrace.first(5)
          end
        end

        logger.info "Auto-merge process completed",
                    merged_count: merged.size,
                    failed_count: failed.size

        {
          merged_count: merged.size,
          failed_count: failed.size,
          details: {
            merged: merged,
            failed: failed,
          },
        }
      end

      private

      def find_approved_prs
        logger.debug "Searching for PRs with soba:lgtm label"
        @github_client.search_pull_requests(repository: @repository, labels: ["soba:lgtm"])
      rescue => e
        logger.error "Failed to find approved PRs", error: e.message
        []
      end

      def check_mergeable(pr_number)
        logger.debug "Checking if PR is mergeable", pr_number: pr_number

        pr = @github_client.get_pull_request(@repository, pr_number)

        # Check both mergeable flag and mergeable_state
        # mergeable_state can be: "clean", "dirty", "unknown", "blocked", "behind", "unstable", "has_hooks", "draft"
        is_mergeable = pr[:mergeable] == true && pr[:mergeable_state] == "clean"

        logger.debug "PR mergeable status",
                     pr_number: pr_number,
                     mergeable: pr[:mergeable],
                     mergeable_state: pr[:mergeable_state],
                     is_mergeable: is_mergeable

        is_mergeable
      rescue => e
        logger.error "Failed to check mergeable status", pr_number: pr_number, error: e.message
        false
      end

      def perform_merge(pr_number)
        logger.info "Merging PR", pr_number: pr_number, merge_method: "squash"

        @github_client.merge_pull_request(@repository, pr_number, merge_method: "squash")
      end

      def handle_post_merge(pr_number, sha: nil)
        logger.debug "Handling post-merge actions", pr_number: pr_number

        # Extract issue number from PR body
        issue_number = @github_client.get_pr_issue_number(@repository, pr_number)

        if issue_number
          logger.info "Closing related issue", pr_number: pr_number, issue_number: issue_number
          @github_client.close_issue_with_label(@repository, issue_number, label: "soba:merged")

          # Send Slack notification for merged issue
          send_merge_notification(issue_number, pr_number, sha)
        else
          logger.warn "No related issue found in PR body", pr_number: pr_number
        end
      rescue => e
        logger.error "Failed to handle post-merge actions", pr_number: pr_number, error: e.message
      end

      def send_merge_notification(issue_number, pr_number, sha)
        slack_notifier = SlackNotifier.from_config
        return unless slack_notifier&.enabled?

        begin
          pr_data = @github_client.get_pull_request(@repository, pr_number)
          issue_data = @github_client.issue(@repository, issue_number)

          merge_data = {
            issue_number: issue_number,
            issue_title: issue_data[:title],
            pr_number: pr_number,
            pr_title: pr_data[:title],
            sha: sha,
            repository: @repository,
          }

          slack_notifier.notify_issue_merged(merge_data)
          logger.debug "Slack notification sent for merged issue", issue_number: issue_number
        rescue => e
          logger.warn "Failed to send Slack notification for merged issue",
                      issue_number: issue_number,
                      error: e.message
        end
      end
    end
  end
end