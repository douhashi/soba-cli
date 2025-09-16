# frozen_string_literal: true

require 'spec_helper'
require 'soba/container'

RSpec.describe 'Tmux Workflow E2E', type: :e2e, skip: 'Requires actual tmux installation' do
  let(:workflow_executor) { Soba::Container['services.workflow_executor'] }
  let(:tmux_session_manager) { Soba::Container['services.tmux_session_manager'] }

  describe 'Complete workflow with tmux' do
    it 'simulates a full Claude Code workflow in tmux' do
      # Simulate a planning phase
      plan_phase = double(
        command: 'echo',
        options: ['Planning'],
        parameter: 'issue {{issue-number}}'
      )

      # Execute planning in tmux
      plan_result = workflow_executor.execute_in_tmux(
        phase: plan_phase,
        issue_number: 42
      )

      expect(plan_result[:success]).to be true
      plan_session = plan_result[:session_name]

      # Check session status
      status = tmux_session_manager.get_session_status(plan_session)
      expect(status[:exists]).to be true

      # Get attach command (for user interaction)
      attach_result = tmux_session_manager.attach_to_session(plan_session)
      expect(attach_result[:success]).to be true
      expect(attach_result[:command]).to eq("tmux attach-session -t #{plan_session}")

      # Simulate implementation phase
      impl_phase = double(
        command: 'echo',
        options: ['Implementing'],
        parameter: 'feature for issue {{issue-number}}'
      )

      impl_result = workflow_executor.execute_in_tmux(
        phase: impl_phase,
        issue_number: 42
      )

      expect(impl_result[:success]).to be true
      impl_session = impl_result[:session_name]

      # List all Claude sessions
      sessions = tmux_session_manager.list_claude_sessions
      expect(sessions).to include(plan_session, impl_session)

      # Clean up both sessions
      tmux_session_manager.stop_claude_session(plan_session)
      tmux_session_manager.stop_claude_session(impl_session)

      # Verify cleanup
      sessions_after = tmux_session_manager.list_claude_sessions
      expect(sessions_after).not_to include(plan_session, impl_session)
    end

    it 'handles multiple concurrent Claude Code sessions' do
      sessions = []

      # Start multiple sessions
      3.times do |i|
        phase = double(
          command: 'echo',
          options: ["Task-#{i}"],
          parameter: 'for issue {{issue-number}}'
        )

        result = workflow_executor.execute_in_tmux(
          phase: phase,
          issue_number: 100 + i
        )

        expect(result[:success]).to be true
        sessions << result[:session_name]
      end

      # Verify all sessions exist
      active_sessions = tmux_session_manager.list_claude_sessions
      sessions.each do |session|
        expect(active_sessions).to include(session)
      end

      # Clean up all sessions
      sessions.each do |session|
        tmux_session_manager.stop_claude_session(session)
      end

      # Verify all sessions are cleaned
      final_sessions = tmux_session_manager.list_claude_sessions
      sessions.each do |session|
        expect(final_sessions).not_to include(session)
      end
    end
  end
end