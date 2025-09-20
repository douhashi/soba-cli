# frozen_string_literal: true

require "logger"

module Soba
  module Services
    class WorkflowBlockingChecker
      ACTIVE_LABELS = %w(
        soba:queued
        soba:planning
        soba:ready
        soba:doing
        soba:reviewing
        soba:revising
      ).freeze

      INTERMEDIATE_LABELS = %w(
        soba:review-requested
        soba:requires-changes
        soba:done
        soba:merged
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
        # 引数で渡されたissuesからACTIVE_LABELSまたはINTERMEDIATE_LABELSを持つものを検出
        # except_issue_numberが指定されている場合は、そのissueを除外
        blocking = issues.select do |issue|
          if except_issue_number && issue.number == except_issue_number
            next false
          end

          issue.labels.any? do |label|
            label_name = label.is_a?(Hash) ? label[:name] : label.name
            ACTIVE_LABELS.include?(label_name) || INTERMEDIATE_LABELS.include?(label_name)
          end
        end

        logger&.debug("Found #{blocking.size} blocking issues with ACTIVE_LABELS or INTERMEDIATE_LABELS")
        blocking.each do |issue|
          labels = issue.labels.map { |l| l.is_a?(Hash) ? l[:name] : l.name }.
            select { |n| ACTIVE_LABELS.include?(n) || INTERMEDIATE_LABELS.include?(n) }
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
          ACTIVE_LABELS.include?(label_name) || INTERMEDIATE_LABELS.include?(label_name)
        end
        return nil unless label

        label_name = label.is_a?(Hash) ? label[:name] : label.name
        "Issue ##{issue.number} が #{label_name} のため、新しいワークフローの開始をスキップしました"
      end
    end
  end
end