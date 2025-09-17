# frozen_string_literal: true

require "logger"

module Soba
  module Services
    class QueueingService
      TODO_LABEL = "soba:todo"
      QUEUED_LABEL = "soba:queued"

      attr_reader :github_client, :blocking_checker, :logger

      def initialize(github_client:, blocking_checker:, logger: nil)
        @github_client = github_client
        @blocking_checker = blocking_checker
        @logger = logger || Logger.new(STDOUT)
      end

      def queue_next_issue(repository)
        logger.info("キューイング処理を開始します: #{repository}")

        if has_active_issue?(repository)
          issues = github_client.issues(repository, state: "open")
          reason = blocking_checker.blocking_reason(repository, issues: issues)
          logger.info("キューイング処理をスキップします: #{reason}")
          return nil
        end

        candidate = find_next_candidate_from_repository(repository)
        if candidate.nil?
          logger.info("キューイング対象のIssueが見つかりませんでした")
          return nil
        end

        transition_to_queued(candidate)
        candidate
      rescue => e
        logger.error("キューイング処理でエラーが発生しました: #{e.message} (repository: #{repository})")
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
        todo_issues = issues.select do |issue|
          issue.labels.any? { |label| label[:name] == TODO_LABEL }
        end

        return nil if todo_issues.empty?

        # Issue番号の昇順でソートして最初の1件を返す
        todo_issues.min_by(&:number)
      end

      def transition_to_queued(issue)
        logger.debug("Issue ##{issue.number} のラベルを更新します: #{TODO_LABEL} -> #{QUEUED_LABEL}")

        github_client.update_issue_labels(issue.number, from: TODO_LABEL, to: QUEUED_LABEL)

        logger.info("Issue ##{issue.number} を soba:queued に遷移させました: #{issue.title}")
      rescue => e
        logger.error("Issue ##{issue.number} のラベル更新に失敗しました: #{e.message}")
        raise
      end
    end
  end
end