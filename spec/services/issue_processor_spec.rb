# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/issue_processor'
require 'soba/services/workflow_executor'
require 'soba/services/tmux_session_manager'
require 'soba/domain/phase_strategy'
require 'soba/configuration'

RSpec.describe Soba::Services::IssueProcessor do
  let(:github_client) { double('GitHubClient') }
  let(:workflow_executor) { instance_double(Soba::Services::WorkflowExecutor) }
  let(:phase_strategy) { Soba::Domain::PhaseStrategy.new }
  let(:config) { Soba::Configuration }
  let(:processor) do
    described_class.new(
      github_client: github_client,
      workflow_executor: workflow_executor,
      phase_strategy: phase_strategy,
      config: config
    )
  end

  before do
    Soba::Configuration.reset_config
    Soba::Configuration.configure do |c|
      c.github.repository = 'owner/repo'
      c.phase.plan.command = 'echo'
      c.phase.plan.options = ['--test']
      c.phase.plan.parameter = 'Plan {{issue-number}}'
      c.phase.implement.command = 'echo'
      c.phase.implement.options = ['--test']
      c.phase.implement.parameter = 'Implement {{issue-number}}'
    end
  end

  describe '#process' do
    let(:issue) do
      {
        number: 123,
        title: 'Test Issue',
        labels: issue_labels,
      }
    end

    context 'when issue has soba:queued label' do
      let(:issue_labels) { ['soba:queued'] }

      it 'transitions from queued to planning and executes workflow' do
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo',
          issue[:number],
          from: 'soba:queued',
          to: 'soba:planning'
        )

        expect(workflow_executor).to receive(:execute).with(
          phase: anything,
          issue_number: 123,
          issue_title: 'Test Issue',
          phase_name: 'queued_to_planning',
          use_tmux: true,
          setup_workspace: true
        ).and_return({ success: true, mode: 'tmux' })

        result = processor.process(issue)

        expect(result[:success]).to be true
        expect(result[:phase]).to eq(:queued_to_planning)
        expect(result[:label_updated]).to be true
      end
    end

    context 'when issue needs plan phase' do
      let(:issue_labels) { ['soba:todo', 'enhancement'] }

      it 'updates label and executes workflow in tmux by default' do
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo',
          issue[:number],
          from: 'soba:todo',
          to: 'soba:planning'
        )

        expect(workflow_executor).to receive(:execute).with(
          phase: anything,
          issue_number: 123,
          issue_title: 'Test Issue',
          phase_name: 'plan',
          use_tmux: true,
          setup_workspace: true
        ).and_return({ success: true, session_name: 'soba-repo', window_name: 'issue-123', mode: 'tmux' })

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          phase: :plan,
          issue_number: 123,
          label_updated: true
        )
      end

      context 'when workflow execution fails' do
        it 'returns failure result' do
          expect(github_client).to receive(:update_issue_labels).with(
            'owner/repo',
            issue[:number],
            from: 'soba:todo',
            to: 'soba:planning'
          )

          expect(workflow_executor).to receive(:execute).with(
            phase: anything,
            issue_number: 123,
            issue_title: 'Test Issue',
            phase_name: 'plan',
            use_tmux: true,
            setup_workspace: true
          ).and_return({ success: false, error: 'Command failed', mode: 'tmux' })

          result = processor.process(issue)

          expect(result).to include(
            success: false,
            phase: :plan,
            issue_number: 123,
            error: 'Command failed'
          )
        end
      end

      context 'when label update fails' do
        it 'does not execute workflow and returns error' do
          expect(github_client).to receive(:update_issue_labels).with(
            'owner/repo',
            issue[:number],
            from: 'soba:todo',
            to: 'soba:planning'
          ).and_raise(
            StandardError.new('API error')
          )

          expect(workflow_executor).not_to receive(:execute)

          expect do
            processor.process(issue)
          end.to raise_error(Soba::Services::IssueProcessingError, /Failed to update labels/)
        end
      end
    end

    context 'when issue needs implement phase' do
      let(:issue_labels) { ['soba:ready'] }

      it 'updates label to soba:doing and executes workflow in tmux' do
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo',
          issue[:number],
          from: 'soba:ready',
          to: 'soba:doing'
        )

        expect(workflow_executor).to receive(:execute).with(
          phase: anything,
          issue_number: 123,
          issue_title: 'Test Issue',
          phase_name: 'implement',
          use_tmux: true,
          setup_workspace: true
        ).and_return({ success: true, session_name: 'soba-repo', window_name: 'issue-123', mode: 'tmux' })

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          phase: :implement,
          issue_number: 123,
          label_updated: true
        )
      end
    end

    context 'when use_tmux is disabled in configuration' do
      let(:issue_labels) { ['soba:todo'] }

      before do
        Soba::Configuration.configure do |c|
          c.workflow.use_tmux = false
        end
      end

      it 'executes workflow directly without tmux' do
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo',
          issue[:number],
          from: 'soba:todo',
          to: 'soba:planning'
        )

        expect(workflow_executor).to receive(:execute).with(
          phase: anything,
          issue_number: 123,
          issue_title: 'Test Issue',
          phase_name: 'plan',
          use_tmux: false,
          setup_workspace: true
        ).and_return({ success: true, output: 'Plan phase started', mode: 'direct' })

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          phase: :plan,
          issue_number: 123,
          label_updated: true
        )
      end
    end

    context 'when issue is already in progress' do
      let(:issue_labels) { ['soba:planning'] }

      it 'returns skipped result' do
        expect(github_client).not_to receive(:update_issue_labels)
        expect(workflow_executor).not_to receive(:execute)

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          skipped: true,
          reason: 'No phase determined for issue'
        )
      end
    end

    context 'when issue has no soba labels' do
      let(:issue_labels) { ['bug', 'enhancement'] }

      it 'returns skipped result' do
        expect(github_client).not_to receive(:update_issue_labels)
        expect(workflow_executor).not_to receive(:execute)

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          skipped: true,
          reason: 'No phase determined for issue'
        )
      end
    end

    context 'when phase config is not defined' do
      let(:issue_labels) { ['soba:todo'] }

      before do
        Soba::Configuration.configure do |c|
          c.phase.plan.command = nil
          c.phase.plan.options = []
          c.phase.plan.parameter = nil
        end
      end

      it 'updates label but skips workflow execution' do
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo',
          issue[:number],
          from: 'soba:todo',
          to: 'soba:planning'
        )

        expect(workflow_executor).not_to receive(:execute)

        result = processor.process(issue)

        expect(result).to include(
          success: true,
          phase: :plan,
          issue_number: 123,
          label_updated: true,
          workflow_skipped: true,
          reason: 'Phase configuration not defined'
        )
      end
    end
  end

  describe '#current_label_for_phase' do
    it 'returns correct label for plan phase' do
      result = processor.send(:current_label_for_phase, :plan)

      expect(result).to eq('soba:todo')
    end

    it 'returns correct label for implement phase' do
      result = processor.send(:current_label_for_phase, :implement)

      expect(result).to eq('soba:ready')
    end
  end
end