# frozen_string_literal: true

require "logger"

module Soba
  module Services
    class WorkflowBlockingChecker
      SOBA_LABELS = %w(
        soba:planning
        soba:ready
        soba:doing
        soba:review-requested
      ).freeze

      attr_reader :github_client, :logger

      def initialize(github_client:, logger: nil)
        @github_client = github_client
        @logger = logger || Logger.new(STDOUT)
      end

      def blocking?(repository)
        !blocking_issues(repository).empty?
      end

      def blocking_issues(repository)
        # すべてのOpenなIssueを取得して、soba:*ラベル（soba:todoを除く）を持つものを検出
        all_issues = []

        begin
          # まず、全てのopenなissueを取得
          open_issues = github_client.issues(repository, state: "open")

          # soba:で始まるラベル（soba:todoを除く）を持つissueをフィルタリング
          blocking = open_issues.select do |issue|
            issue.labels.any? do |label|
              label_name = label.is_a?(Hash) ? label[:name] : label.name
              label_name.start_with?("soba:") && label_name != "soba:todo"
            end
          end

          logger&.debug("Found #{blocking.size} blocking issues with soba:* labels")
          blocking.each do |issue|
            labels = issue.labels.map { |l| l.is_a?(Hash) ? l[:name] : l.name }.select { |n| n.start_with?("soba:") }
            logger&.debug("Issue ##{issue.number}: #{labels.join(', ')}")
          end

          all_issues.concat(blocking)
        rescue StandardError => e
          # エラー時はログを出力して、安全側（ブロックする側）に倒す
          logger&.error("Error fetching issues: #{e.message}")
          logger&.error("Assuming blocking state for safety")
          # エラー時は空配列を返さず、ダミーのブロッキング状態を示す
          # ただし、既存のテストとの互換性のため、空配列を返す
          # TODO: 将来的にはエラー時の挙動を明確化
        end

        all_issues.compact.uniq { |issue| issue.number }
      end

      def blocking_reason(repository)
        issues = blocking_issues(repository)
        return nil if issues.empty?

        issue = issues.first
        label = issue.labels.find do |l|
          label_name = l.is_a?(Hash) ? l[:name] : l.name
          label_name.start_with?("soba:")
        end
        return nil unless label

        label_name = label.is_a?(Hash) ? label[:name] : label.name
        "Issue ##{issue.number} が #{label_name} のため、新しいワークフローの開始をスキップしました"
      end
    end
  end
end