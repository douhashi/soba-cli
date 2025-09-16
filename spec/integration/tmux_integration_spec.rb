# frozen_string_literal: true

require 'spec_helper'
require 'soba/container'

RSpec.describe 'Tmux Integration', type: :integration, skip: 'Requires actual tmux installation' do
  let(:tmux_client) { Soba::Container['tmux.client'] }
  let(:tmux_session_manager) { Soba::Container['services.tmux_session_manager'] }
  let(:workflow_executor) { Soba::Container['services.workflow_executor'] }

  describe 'TmuxClient and TmuxSessionManager integration' do
    let(:issue_number) { 99 }
    let(:test_session_name) { "soba-test-integration-#{Time.now.to_i}" }

    after do
      # Clean up any test sessions
      tmux_client.kill_session(test_session_name) if tmux_client.session_exists?(test_session_name)
    end

    it 'can create and manage a tmux session' do
      # Create session through manager
      result = tmux_session_manager.start_claude_session(
        issue_number: issue_number,
        command: 'echo "Integration test"'
      )

      expect(result[:success]).to be true
      session_name = result[:session_name]

      # Verify session exists
      expect(tmux_client.session_exists?(session_name)).to be true

      # Get session status
      status = tmux_session_manager.get_session_status(session_name)
      expect(status[:exists]).to be true
      expect(status[:status]).to eq('running')

      # Stop session
      stop_result = tmux_session_manager.stop_claude_session(session_name)
      expect(stop_result[:success]).to be true

      # Verify session is gone
      expect(tmux_client.session_exists?(session_name)).to be false
    end

    it 'lists only claude sessions' do
      # Create a test session
      tmux_client.create_session(test_session_name)

      # Create a claude session
      result = tmux_session_manager.start_claude_session(
        issue_number: issue_number,
        command: 'ls'
      )
      claude_session_name = result[:session_name]

      # List claude sessions
      claude_sessions = tmux_session_manager.list_claude_sessions
      expect(claude_sessions).to include(claude_session_name)
      expect(claude_sessions).not_to include(test_session_name)

      # Clean up
      tmux_session_manager.stop_claude_session(claude_session_name)
    end
  end

  describe 'WorkflowExecutor and TmuxSessionManager integration' do
    let(:phase_config) do
      double(
        command: 'echo',
        options: ['Integration'],
        parameter: 'test {{issue-number}}'
      )
    end

    it 'executes workflow in tmux session' do
      result = workflow_executor.execute_in_tmux(
        phase: phase_config,
        issue_number: 88
      )

      expect(result[:success]).to be true
      expect(result[:mode]).to eq('tmux')
      expect(result[:session_name]).to match(/^soba-claude-88-\d+$/)

      # Verify session exists
      expect(tmux_client.session_exists?(result[:session_name])).to be true

      # Clean up
      tmux_session_manager.stop_claude_session(result[:session_name])
    end

    it 'can switch between standard and tmux execution modes' do
      # Standard execution
      standard_result = workflow_executor.execute(
        phase: phase_config,
        issue_number: 77
      )
      expect(standard_result[:success]).to be true
      expect(standard_result).not_to have_key(:mode)

      # Tmux execution
      tmux_result = workflow_executor.execute_in_tmux(
        phase: phase_config,
        issue_number: 77
      )
      expect(tmux_result[:success]).to be true
      expect(tmux_result[:mode]).to eq('tmux')

      # Clean up
      tmux_session_manager.stop_claude_session(tmux_result[:session_name])
    end
  end

  describe 'Session cleanup' do
    it 'can cleanup old sessions based on age' do
      # Create old and new sessions with controlled timestamps
      old_issue = 55
      new_issue = 66

      # Start old session (we'll pretend it's old by its name)
      old_time = Time.now.to_i - 7200 # 2 hours ago
      old_session_name = "soba-claude-#{old_issue}-#{old_time}"
      tmux_client.create_session(old_session_name)

      # Start new session
      new_result = tmux_session_manager.start_claude_session(
        issue_number: new_issue,
        command: 'sleep 1'
      )
      new_session_name = new_result[:session_name]

      # Run cleanup (sessions older than 1 hour)
      cleanup_result = tmux_session_manager.cleanup_old_sessions(max_age_seconds: 3600)

      # Verify old session was cleaned
      expect(cleanup_result[:cleaned]).to include(old_session_name)
      expect(tmux_client.session_exists?(old_session_name)).to be false

      # Verify new session still exists
      expect(tmux_client.session_exists?(new_session_name)).to be true

      # Clean up remaining session
      tmux_session_manager.stop_claude_session(new_session_name)
    end
  end

  describe 'Window and pane operations' do
    let(:test_session_name) { "soba-test-windows-#{Time.now.to_i}" }

    after do
      tmux_client.kill_session(test_session_name) if tmux_client.session_exists?(test_session_name)
    end

    it 'manages windows within a session' do
      # Create session
      expect(tmux_client.create_session(test_session_name)).to be true

      # Create a new window
      expect(tmux_client.create_window(test_session_name, 'test-window')).to be true

      # List windows
      windows = tmux_client.list_windows(test_session_name)
      expect(windows).to include('test-window')

      # Rename window
      expect(tmux_client.rename_window(test_session_name, 'test-window', 'renamed-window')).to be true

      # Switch window
      expect(tmux_client.switch_window(test_session_name, 'renamed-window')).to be true
    end

    it 'manages panes within a session' do
      # Create session
      expect(tmux_client.create_session(test_session_name)).to be true

      # Split panes
      expect(tmux_client.split_pane(test_session_name, :vertical)).to be true
      expect(tmux_client.split_pane(test_session_name, :horizontal)).to be true

      # Select pane
      expect(tmux_client.select_pane(test_session_name, 0)).to be true

      # Resize pane
      expect(tmux_client.resize_pane(test_session_name, :down, 5)).to be true

      # Close a pane (not pane 0, which would close the session)
      expect(tmux_client.close_pane(test_session_name, 1)).to be true
    end
  end

  describe 'Session information' do
    let(:test_session_name) { "soba-test-info-#{Time.now.to_i}" }

    after do
      tmux_client.kill_session(test_session_name) if tmux_client.session_exists?(test_session_name)
    end

    it 'retrieves detailed session information' do
      # Create session
      expect(tmux_client.create_session(test_session_name)).to be true

      # Get session info
      info = tmux_client.session_info(test_session_name)
      expect(info).to be_a(Hash)
      expect(info[:name]).to eq(test_session_name)
      expect(info[:windows]).to be >= 1
      expect(info[:created_at]).to be_a(String)
      expect(info[:size]).to be_an(Array)

      # Check attached status
      attached = tmux_client.session_attached?(test_session_name)
      expect(attached).to be_in([true, false])
    end
  end
end