# frozen_string_literal: true

module Soba
  module Services
    class WorkflowBlockingChecker
      SOBA_LABELS = %w(
        soba:planning
        soba:ready
        soba:doing
        soba:review-requested
      ).freeze

      attr_reader :github_client

      def initialize(github_client:)
        @github_client = github_client
      end

      def blocking?(repository)
        !blocking_issues(repository).empty?
      end

      def blocking_issues(repository)
        SOBA_LABELS.flat_map do |label|
          github_client.issues(repository, state: "open", labels: label)
        rescue StandardError
          []
        end.compact
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