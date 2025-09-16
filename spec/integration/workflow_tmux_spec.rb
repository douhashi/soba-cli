# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/workflow_executor'
require 'soba/services/tmux_session_manager'
require 'soba/infrastructure/tmux_client'
require 'soba/services/issue_processor'
require 'soba/infrastructure/github_client'
require 'soba/domain/phase_strategy'
require 'soba/configuration'

RSpec.describe 'Workflow Tmux Integration' do
  let(:tmux_client) { Soba::Infrastructure::TmuxClient.new }
  let(:tmux_session_manager) { Soba::Services::TmuxSessionManager.new(tmux_client: tmux_client) }
  let(:workflow_executor) { Soba::Services::WorkflowExecutor.new(tmux_session_manager: tmux_session_manager) }
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:phase_strategy) { Soba::Domain::PhaseStrategy.new }
  let(:issue_processor) do
    Soba::Services::IssueProcessor.new(
      github_client: github_client,
      workflow_executor: workflow_executor,
      phase_strategy: phase_strategy,
      config: Soba::Configuration
    )
  end

  before do
    Soba::Configuration.reset_config
    Soba::Configuration.configure do |c|
      c.github.token = 'test_token'
      c.github.repository = 'test/repo'
      c.workflow.use_tmux = true
      c.phase.plan.command = 'echo'
      c.phase.plan.options = ['-n']
      c.phase.plan.parameter = 'Planning issue {{issue-number}}'
    end

    # Mock TmuxClient within TmuxSessionManager
    allow_any_instance_of(Soba::Infrastructure::TmuxClient).to receive(:create_session).
      and_return(success: true)
    allow_any_instance_of(Soba::Infrastructure::TmuxClient).to receive(:send_keys).
      and_return(success: true)
  end

  describe 'default tmux mode execution' do
    it 'executes workflow in tmux by default' do
      issue = {
        number: 123,
        title: 'Test Issue',
        labels: ['soba:todo'],
      }

      expect(github_client).to receive(:update_issue_labels).with(
        123,
        from: 'soba:todo',
        to: 'soba:planning'
      )

      result = issue_processor.process(issue)

      expect(result).to include(
        success: true,
        phase: :plan,
        mode: 'tmux'
      )
      expect(result[:session_name]).to match(/^soba-claude-123-\d+$/)
    end

    it 'respects use_tmux: false configuration' do
      Soba::Configuration.configure do |c|
        c.workflow.use_tmux = false
      end

      issue = {
        number: 456,
        title: 'Direct execution test',
        labels: ['soba:todo'],
      }

      expect(github_client).to receive(:update_issue_labels).with(
        456,
        from: 'soba:todo',
        to: 'soba:planning'
      )

      allow(Open3).to receive(:popen3).with('echo', '-n', 'Planning issue 456') do |&block|
        stdin = double('stdin', close: nil)
        stdout = double('stdout', read: 'Planning issue 456')
        stderr = double('stderr', read: '')
        thread = double('thread', value: double(exitstatus: 0))
        block.call(stdin, stdout, stderr, thread)
      end

      result = issue_processor.process(issue)

      expect(result).to include(
        success: true,
        phase: :plan,
        output: 'Planning issue 456'
      )
      expect(result).not_to have_key(:mode)
      expect(result).not_to have_key(:session_name)
    end
  end

  describe 'tmux session naming' do
    it 'generates unique session names for different issues' do
      phase_config = double(
        command: 'echo',
        options: ['-n'],
        parameter: 'Test {{issue-number}}'
      )

      result1 = workflow_executor.execute(phase: phase_config, issue_number: 100)
      result2 = workflow_executor.execute(phase: phase_config, issue_number: 200)

      expect(result1[:session_name]).to match(/^soba-claude-100-\d+$/)
      expect(result2[:session_name]).to match(/^soba-claude-200-\d+$/)
      expect(result1[:session_name]).not_to eq(result2[:session_name])
    end
  end
end