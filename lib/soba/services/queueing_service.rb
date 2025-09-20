# frozen_string_literal: true

module Soba
  module Services
    class QueueingService
      TODO_LABEL = "soba:todo"
      QUEUED_LABEL = "soba:queued"

      attr_reader :github_client, :blocking_checker, :logger

      def initialize(github_client:, blocking_checker:, logger: nil)
        @github_client = github_client
        @blocking_checker = blocking_checker
        @logger = logger || SemanticLogger["QueueingService"]
      end

      def queue_next_issue(repository)
        logger.info("Starting queueing process: #{repository}")

        if has_active_issue?(repository)
          issues = github_client.issues(repository, state: "open")
          reason = blocking_checker.blocking_reason(repository, issues: issues)
          logger.info("Skipping queueing process: #{reason}")
          return nil
        end

        candidate = find_next_candidate_from_repository(repository)
        if candidate.nil?
          logger.info("No issues found for queueing")
          return nil
        end

        result = transition_to_queued(candidate, repository)
        return nil if result.nil? # 競合状態検出時

        candidate
      rescue => e
        logger.error("Error during queueing process: #{e.message} (repository: #{repository})")
        raise
      end

      private

      def has_active_issue?(repository)
        issues = github_client.issues(repository, state: "open")
        blocking_checker.blocking?(repository, issues: issues)
      end

      def find_next_candidate_from_repository(repository)
        issues = github_client.issues(repository, state: "open")
        find_next_candidate(issues)
      end

      def find_next_candidate(issues)
        # アクティブまたは中間状態のsobaラベルを持つIssueが存在する場合はnilを返す
        active_or_intermediate_issues = issues.select do |issue|
          issue.labels.any? do |label|
            label_name = label[:name]
            WorkflowBlockingChecker::ACTIVE_LABELS.include?(label_name) ||
              WorkflowBlockingChecker::INTERMEDIATE_LABELS.include?(label_name)
          end
        end

        return nil unless active_or_intermediate_issues.empty?

        todo_issues = issues.select do |issue|
          issue.labels.any? { |label| label[:name] == TODO_LABEL }
        end

        return nil if todo_issues.empty?

        # Issue番号の昇順でソートして最初の1件を返す
        todo_issues.min_by(&:number)
      end

      def transition_to_queued(issue, repository)
        # ラベル更新直前に再度排他制御チェック（競合状態の検出）
        current_issues = github_client.issues(repository, state: "open")
        if blocking_checker.blocking?(repository, issues: current_issues)
          reason = blocking_checker.blocking_reason(repository, issues: current_issues)
          logger.warn("Race condition detected: #{reason}")
          logger.warn("Skipping queueing for Issue ##{issue.number}")
          return nil
        end

        logger.debug("Updating labels for Issue ##{issue.number}: #{TODO_LABEL} -> #{QUEUED_LABEL}")

        github_client.update_issue_labels(repository, issue.number, from: TODO_LABEL, to: QUEUED_LABEL)

        logger.info("Transitioned Issue ##{issue.number} to soba:queued: #{issue.title}")
        true  # 成功を示すために true を返す
      rescue => e
        logger.error("Failed to update labels for Issue ##{issue.number}: #{e.message}")
        raise
      end
    end
  end
end