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

      def blocking?(repository, issues:, except_issue_number: nil)
        !blocking_issues(repository, issues: issues, except_issue_number: except_issue_number).empty?
      end

      def blocking_issues(repository, issues:, except_issue_number: nil)
        # 引数で渡されたissuesからsoba:*ラベル（soba:todoを除く）を持つものを検出
        # except_issue_numberが指定されている場合は、そのissueを除外
        blocking = issues.select do |issue|
          if except_issue_number && issue.number == except_issue_number
            next false
          end

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

        blocking.compact.uniq { |issue| issue.number }
      end

      def blocking_reason(repository, issues:, except_issue_number: nil)
        blocking = blocking_issues(repository, issues: issues, except_issue_number: except_issue_number)
        return nil if blocking.empty?

        issue = blocking.first
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