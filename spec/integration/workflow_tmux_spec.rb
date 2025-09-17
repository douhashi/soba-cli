# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/workflow_executor'
require 'soba/services/tmux_session_manager'
require 'soba/infrastructure/tmux_client'
require 'soba/configuration'

RSpec.describe 'Workflow Tmux Integration' do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:tmux_session_manager) { Soba::Services::TmuxSessionManager.new(tmux_client: tmux_client) }
  let(:git_workspace_manager) { instance_double(Soba::Services::GitWorkspaceManager) }
  let(:workflow_executor) { Soba::Services::WorkflowExecutor.new(tmux_session_manager: tmux_session_manager, git_workspace_manager: git_workspace_manager) }

  before do
    allow(Soba::Configuration).to receive(:config).and_return(
      double(github: double(repository: 'owner/repo-name'))
    )
    allow(git_workspace_manager).to receive(:setup_workspace)
    allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
  end

  describe 'executing workflow in new tmux structure' do
    let(:issue_number) { 42 }
    let(:phase) do
      double(
        name: 'planning',
        command: 'soba:plan',
        options: [],
        parameter: '{{issue-number}}'
      )
    end

    context 'when executing in a new repository session' do
      before do
        # Repository session doesn't exist
        allow(tmux_client).to receive(:session_exists?).with('soba-owner-repo-name').and_return(false)
        allow(tmux_client).to receive(:create_session).with('soba-owner-repo-name').and_return(true)

        # Window doesn't exist (new issue)
        allow(tmux_client).to receive(:window_exists?).with('soba-owner-repo-name', 'issue-42').and_return(false)
        allow(tmux_client).to receive(:create_window).with('soba-owner-repo-name', 'issue-42').and_return(true)

        # Send command to the first pane
        allow(tmux_client).to receive(:send_keys).with('soba-owner-repo-name:issue-42', 'soba:plan 42').and_return(true)
      end

      it 'creates repository session, issue window, and executes command' do
        # WorkflowExecutor needs tmux_client instance
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)

        result = workflow_executor.execute(phase: phase, issue_number: issue_number, use_tmux: true)

        expect(result[:success]).to be true
        expect(result[:session_name]).to eq('soba-owner-repo-name')
        expect(result[:window_name]).to eq('issue-42')
        expect(result[:pane_id]).to be_nil # First pane, no split
        expect(result[:mode]).to eq('tmux')

        expect(tmux_client).to have_received(:create_session).with('soba-owner-repo-name')
        expect(tmux_client).to have_received(:create_window).with('soba-owner-repo-name', 'issue-42')
        expect(tmux_client).to have_received(:send_keys).with('soba-owner-repo-name:issue-42', 'soba:plan 42')
      end
    end

    context 'when executing in an existing session with existing window' do
      before do
        # Repository session exists
        allow(tmux_client).to receive(:session_exists?).with('soba-owner-repo-name').and_return(true)
        allow(tmux_client).to receive(:create_session) # Allow but don't expect

        # Window exists (continuing work on same issue)
        allow(tmux_client).to receive(:window_exists?).with('soba-owner-repo-name', 'issue-42').and_return(true)
        allow(tmux_client).to receive(:create_window) # Allow but don't expect

        # Create new pane for the phase
        allow(tmux_client).to receive(:list_panes).with('soba-owner-repo-name', 'issue-42').and_return([])
        allow(tmux_client).to receive(:split_window).with(
          session_name: 'soba-owner-repo-name',
          window_name: 'issue-42',
          vertical: false
        ).and_return('%15')
        allow(tmux_client).to receive(:select_layout).with('soba-owner-repo-name', 'issue-42', 'even-horizontal').and_return(true)

        # Send command to the new pane
        allow(tmux_client).to receive(:send_keys).with('%15', 'soba:plan 42').and_return(true)
      end

      it 'uses existing session/window and creates new pane for phase' do
        # WorkflowExecutor needs tmux_client instance
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)

        result = workflow_executor.execute(phase: phase, issue_number: issue_number, use_tmux: true)

        expect(result[:success]).to be true
        expect(result[:session_name]).to eq('soba-owner-repo-name')
        expect(result[:window_name]).to eq('issue-42')
        expect(result[:pane_id]).to eq('%15')
        expect(result[:mode]).to eq('tmux')

        expect(tmux_client).not_to have_received(:create_session)
        expect(tmux_client).not_to have_received(:create_window)
        expect(tmux_client).to have_received(:split_window)
        expect(tmux_client).to have_received(:send_keys).with('%15', 'soba:plan 42')
      end
    end

    context 'when repository configuration is missing' do
      before do
        allow(Soba::Configuration).to receive(:config).and_return(
          double(github: double(repository: nil))
        )
      end

      it 'returns an error' do
        result = workflow_executor.execute(phase: phase, issue_number: issue_number, use_tmux: true)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Repository configuration not found/)
      end
    end
  end

  describe 'multiple phases execution' do
    let(:issue_number) { 31 }
    let(:planning_phase) do
      double(
        name: 'planning',
        command: 'soba:plan',
        options: [],
        parameter: '{{issue-number}}'
      )
    end
    let(:implementation_phase) do
      double(
        name: 'implementation',
        command: 'soba:implement',
        options: [],
        parameter: '{{issue-number}}'
      )
    end

    context 'when executing multiple phases for the same issue' do
      before do
        # Repository session exists
        allow(tmux_client).to receive(:session_exists?).with('soba-owner-repo-name').and_return(true)

        # First phase: window doesn't exist
        allow(tmux_client).to receive(:window_exists?).
          with('soba-owner-repo-name', 'issue-31').
          and_return(false, true) # Returns false first time, true second time
        allow(tmux_client).to receive(:create_window).with('soba-owner-repo-name', 'issue-31').and_return(true)
        allow(tmux_client).to receive(:send_keys).with('soba-owner-repo-name:issue-31', 'soba:plan 31').and_return(true)

        # Second phase: window exists, create new pane
        allow(tmux_client).to receive(:list_panes).with('soba-owner-repo-name', 'issue-31').and_return([])
        allow(tmux_client).to receive(:split_window).with(
          session_name: 'soba-owner-repo-name',
          window_name: 'issue-31',
          vertical: false
        ).and_return('%20')
        allow(tmux_client).to receive(:select_layout).with('soba-owner-repo-name', 'issue-31', 'even-horizontal').and_return(true)
        allow(tmux_client).to receive(:send_keys).with('%20', 'soba:implement 31').and_return(true)
      end

      it 'creates window for first phase and pane for second phase' do
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)

        # Execute planning phase
        planning_result = workflow_executor.execute(phase: planning_phase, issue_number: issue_number, use_tmux: true)
        expect(planning_result[:success]).to be true
        expect(planning_result[:pane_id]).to be_nil

        # Execute implementation phase
        implementation_result = workflow_executor.execute(phase: implementation_phase, issue_number: issue_number, use_tmux: true)
        expect(implementation_result[:success]).to be true
        expect(implementation_result[:pane_id]).to eq('%20')

        # Verify the sequence of calls
        expect(tmux_client).to have_received(:create_window).once
        expect(tmux_client).to have_received(:split_window).once
      end
    end
  end
end