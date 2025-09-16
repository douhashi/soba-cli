# frozen_string_literal: true

module Soba
  module Services
    class IssueProcessingError < StandardError; end

    class IssueProcessor
      attr_reader :github_client, :workflow_executor, :phase_strategy, :config

      def initialize(github_client:, workflow_executor:, phase_strategy:, config:)
        @github_client = github_client
        @workflow_executor = workflow_executor
        @phase_strategy = phase_strategy
        @config = config
      end

      def process(issue)
        phase = phase_strategy.determine_phase(issue[:labels])

        return skipped_result('No phase determined for issue') unless phase

        current_label = current_label_for_phase(phase)
        next_label = phase_strategy.next_label(phase)

        begin
          github_client.update_issue_labels(
            issue[:number],
            from: current_label,
            to: next_label
          )
        rescue StandardError => e
          raise IssueProcessingError, "Failed to update labels: #{e.message}"
        end

        phase_config = get_phase_config(phase)

        if phase_config&.command
          execution_result = workflow_executor.execute(
            phase: phase_config,
            issue_number: issue[:number]
          )

          {
            success: execution_result[:success],
            phase: phase,
            issue_number: issue[:number],
            label_updated: true,
            output: execution_result[:output],
            error: execution_result[:error],
          }
        else
          {
            success: true,
            phase: phase,
            issue_number: issue[:number],
            label_updated: true,
            workflow_skipped: true,
            reason: 'Phase configuration not defined',
          }
        end
      end

      private

      def skipped_result(reason)
        {
          success: true,
          skipped: true,
          reason: reason,
        }
      end

      def current_label_for_phase(phase)
        phase_strategy.current_label_for_phase(phase)
      end

      def get_phase_config(phase)
        case phase
        when :plan
          config.config.phase.plan
        when :implement
          config.config.phase.implement
        else
          nil
        end
      end
    end
  end
end