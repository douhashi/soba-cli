# frozen_string_literal: true

require 'ostruct'
require_relative '../configuration'
require_relative '../infrastructure/github_client'
require_relative '../infrastructure/tmux_client'
require_relative '../domain/phase_strategy'
require_relative 'workflow_executor'
require_relative 'tmux_session_manager'
require_relative 'git_workspace_manager'

module Soba
  module Services
    class IssueProcessingError < StandardError; end

    class IssueProcessor
      attr_reader :github_client, :workflow_executor, :phase_strategy, :config

      def initialize(github_client: nil, workflow_executor: nil, phase_strategy: nil, config: nil)
        @github_client = github_client || Infrastructure::GitHubClient.new
        @config = config || Configuration
        @workflow_executor = workflow_executor || WorkflowExecutor.new(
          tmux_session_manager: TmuxSessionManager.new(
            tmux_client: Infrastructure::TmuxClient.new
          ),
          git_workspace_manager: GitWorkspaceManager.new(configuration: @config)
        )
        @phase_strategy = phase_strategy || Domain::PhaseStrategy.new
      end

      def run(issue_number, use_tmux: true)
        # Fetch issue details from GitHub
        repository = get_repository_from_config
        issue = @github_client.issue(repository, issue_number)

        # Convert issue to expected format
        issue_hash = {
          number: issue.number,
          title: issue.title,
          labels: issue.labels.map { |l| l.name || l[:name] },
        }

        # Process with the specified tmux mode
        original_use_tmux = @config.config.workflow.use_tmux
        begin
          # Temporarily override the config value
          @config.config.workflow.use_tmux = use_tmux
          process(issue_hash)
        ensure
          # Restore original config value
          @config.config.workflow.use_tmux = original_use_tmux
        end
      end

      def process(issue)
        phase = phase_strategy.determine_phase(issue[:labels])

        return skipped_result('No phase determined for issue') unless phase

        current_label = current_label_for_phase(phase)
        next_label = phase_strategy.next_label(phase)

        begin
          repository = get_repository_from_config
          github_client.update_issue_labels(
            repository,
            issue[:number],
            from: current_label,
            to: next_label
          )
        rescue StandardError => e
          raise IssueProcessingError, "Failed to update labels: #{e.message}"
        end

        phase_config = get_phase_config(phase)

        if phase_config&.command
          actual_config = config.respond_to?(:config) ? config.config : config
          use_tmux = actual_config.workflow.use_tmux
          setup_workspace = actual_config.git.setup_workspace

          execution_result = workflow_executor.execute(
            phase: phase_config,
            issue_number: issue[:number],
            use_tmux: use_tmux,
            setup_workspace: setup_workspace
          )

          result = {
            success: execution_result[:success],
            phase: phase,
            issue_number: issue[:number],
            label_updated: true,
            output: execution_result[:output],
            error: execution_result[:error],
          }

          # Add tmux-specific fields if present
          result[:mode] = execution_result[:mode] if execution_result[:mode]
          result[:session_name] = execution_result[:session_name] if execution_result[:session_name]
          result[:window_name] = execution_result[:window_name] if execution_result[:window_name]
          result[:pane_id] = execution_result[:pane_id] if execution_result[:pane_id]
          result[:tmux_info] = execution_result[:tmux_info] if execution_result[:tmux_info]

          result
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

      def get_repository_from_config
        actual_config = @config.respond_to?(:config) ? @config.config : @config
        actual_config.github.repository
      end

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
        when :plan, :queued_to_planning
          # config is the Configuration module, get the actual config object
          actual_config = config.respond_to?(:config) ? config.config : config
          plan_config = actual_config.phase.plan

          # Access values through @_values instead of @values
          values = plan_config.instance_variable_get(:@_values)

          if values
            OpenStruct.new(
              command: values[:command],
              options: values[:options],
              parameter: values[:parameter]
            )
          else
            nil
          end
        when :implement
          actual_config = config.respond_to?(:config) ? config.config : config
          impl_config = actual_config.phase.implement
          values = impl_config.instance_variable_get(:@_values)

          if values
            OpenStruct.new(
              command: values[:command],
              options: values[:options],
              parameter: values[:parameter]
            )
          else
            nil
          end
        when :review
          actual_config = config.respond_to?(:config) ? config.config : config
          review_config = actual_config.phase.review
          values = review_config.instance_variable_get(:@_values)

          if values
            OpenStruct.new(
              command: values[:command],
              options: values[:options],
              parameter: values[:parameter]
            )
          else
            nil
          end
        when :revise
          actual_config = config.respond_to?(:config) ? config.config : config
          revise_config = actual_config.phase.revise
          values = revise_config.instance_variable_get(:@_values)

          if values
            OpenStruct.new(
              command: values[:command],
              options: values[:options],
              parameter: values[:parameter]
            )
          else
            nil
          end
        else
          nil
        end
      rescue StandardError
        nil
      end
    end
  end
end