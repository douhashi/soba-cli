# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/workflow_executor'
require 'soba/services/tmux_session_manager'
require 'soba/infrastructure/tmux_client'

RSpec.describe Soba::Services::WorkflowExecutor do
  let(:tmux_session_manager) { instance_double(Soba::Services::TmuxSessionManager) }
  let(:git_workspace_manager) { instance_double(Soba::Services::GitWorkspaceManager) }
  let(:executor) { described_class.new(tmux_session_manager: tmux_session_manager, git_workspace_manager: git_workspace_manager) }

  describe '#execute' do
    let(:phase_config) do
      double(
        command: 'echo',
        options: ['--test'],
        parameter: 'Issue {{issue-number}}'
      )
    end

    context 'with git workspace setup' do
      it 'updates main branch and sets up workspace before executing command' do
        expect(git_workspace_manager).to receive(:update_main_branch).ordered
        expect(git_workspace_manager).to receive(:setup_workspace).with(123).ordered
        expect(git_workspace_manager).to receive(:get_worktree_path).with(123).and_return(nil)
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 123') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 123, use_tmux: false, setup_workspace: true)

        expect(result).to include(success: true)
      end

      it 'continues execution even if main branch update fails' do
        expect(git_workspace_manager).to receive(:update_main_branch).
          and_raise(Soba::Services::GitWorkspaceManager::GitOperationError.new('Git error'))
        expect(git_workspace_manager).to receive(:setup_workspace).with(456)
        expect(git_workspace_manager).to receive(:get_worktree_path).with(456).and_return(nil)
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 456') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 456, use_tmux: false, setup_workspace: true)

        expect(result).to include(success: true)
      end

      it 'continues execution even if workspace setup fails' do
        expect(git_workspace_manager).to receive(:update_main_branch)
        expect(git_workspace_manager).to receive(:setup_workspace).with(456).
          and_raise(Soba::Services::GitWorkspaceManager::GitOperationError.new('Git error'))
        expect(git_workspace_manager).to receive(:get_worktree_path).with(456).and_return(nil)
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 456') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 456, use_tmux: false, setup_workspace: true)

        expect(result).to include(success: true)
      end

      it 'skips main branch update and workspace setup when setup_workspace is false' do
        expect(git_workspace_manager).not_to receive(:update_main_branch)
        expect(git_workspace_manager).not_to receive(:setup_workspace)
        expect(git_workspace_manager).to receive(:get_worktree_path).with(789).and_return(nil)
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 789') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 789, use_tmux: false, setup_workspace: false)

        expect(result).to include(success: true)
      end
    end

    context 'when use_tmux is true (default)' do
      let(:phase_with_name) do
        double(
          name: 'test-phase',
          command: 'echo',
          options: ['--test'],
          parameter: 'Issue {{issue-number}}'
        )
      end
      let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

      before do
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
        allow(tmux_session_manager).to receive(:find_or_create_repository_session).and_return({
          success: true,
          session_name: 'soba-repo',
          created: false,
        })
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'executes the command in tmux session by default' do
        allow(tmux_session_manager).to receive(:create_issue_window).and_return({
          success: true,
          window_name: 'issue-123',
          created: true,
        })
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = executor.execute(phase: phase_with_name, issue_number: 123)

        expect(result).to include(
          success: true,
          session_name: 'soba-repo',
          window_name: 'issue-123',
          mode: 'tmux'
        )
      end

      it 'returns detailed tmux information including monitoring commands' do
        allow(tmux_session_manager).to receive(:create_issue_window).and_return({
          success: true,
          window_name: 'issue-123',
          created: true,
        })
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = executor.execute(phase: phase_with_name, issue_number: 123)

        expect(result).to include(
          success: true,
          session_name: 'soba-repo',
          window_name: 'issue-123',
          mode: 'tmux',
          tmux_info: {
            session: 'soba-repo',
            window: 'issue-123',
            pane: nil,
            monitor_commands: [
              'tmux attach -t soba-repo:issue-123',
              'tmux capture-pane -t soba-repo:issue-123 -p',
            ],
          }
        )
      end

      it 'returns detailed tmux information with pane when existing window' do
        allow(tmux_session_manager).to receive(:create_issue_window).and_return({
          success: true,
          window_name: 'issue-123',
          created: false,
        })
        allow(tmux_session_manager).to receive(:create_phase_pane).and_return({
          success: true,
          pane_id: 'soba-repo:issue-123.1',
        })
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = executor.execute(phase: phase_with_name, issue_number: 123)

        expect(result).to include(
          success: true,
          session_name: 'soba-repo',
          window_name: 'issue-123',
          pane_id: 'soba-repo:issue-123.1',
          mode: 'tmux',
          tmux_info: {
            session: 'soba-repo',
            window: 'issue-123',
            pane: 'soba-repo:issue-123.1',
            monitor_commands: [
              'tmux attach -t soba-repo:issue-123.1',
              'tmux capture-pane -t soba-repo:issue-123.1 -p',
            ],
          }
        )
      end

      it 'explicitly uses tmux when use_tmux is true' do
        allow(tmux_session_manager).to receive(:create_issue_window).and_return({
          success: true,
          window_name: 'issue-456',
          created: true,
        })
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = executor.execute(phase: phase_with_name, issue_number: 456, use_tmux: true)

        expect(result).to include(
          success: true,
          session_name: 'soba-repo',
          window_name: 'issue-456',
          mode: 'tmux'
        )
      end
    end

    context 'when use_tmux is false' do
      before do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'executes the command directly without tmux' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 789') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 789, use_tmux: false)

        expect(result).to include(
          success: true,
          output: 'Command output',
          error: '',
          exit_code: 0
        )
        expect(result).not_to have_key(:mode)
      end
    end

    context 'when executing commands directly (legacy behavior)' do
      before do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'replaces {{issue-number}} placeholder with actual issue number' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 456') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Issue 456')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 456, use_tmux: false)

        expect(result[:output]).to eq('Issue 456')
      end

      it 'handles command failure' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 789') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: 'Command failed')
          thread = double('thread', value: double(exitstatus: 1))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 789, use_tmux: false)

        expect(result).to include(
          success: false,
          output: '',
          error: 'Command failed',
          exit_code: 1
        )
      end

      context 'when options are empty' do
        let(:phase_config) do
          double(
            command: 'echo',
            options: [],
            parameter: 'Hello {{issue-number}}'
          )
        end

        it 'executes command without options' do
          expect(Open3).to receive(:popen3).with('echo', 'Hello 100') do |&block|
            stdin = double('stdin', close: nil)
            stdout = double('stdout', read: 'Hello 100')
            stderr = double('stderr', read: '')
            thread = double('thread', value: double(exitstatus: 0))
            block.call(stdin, stdout, stderr, thread)
          end

          result = executor.execute(phase: phase_config, issue_number: 100, use_tmux: false)

          expect(result[:success]).to be true
        end
      end
    end

    context 'when phase configuration is nil' do
      let(:phase_config) { double(command: nil, options: nil, parameter: nil) }

      before do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'returns nil' do
        result = executor.execute(phase: phase_config, issue_number: 123)

        expect(result).to be_nil
      end
    end

    context 'when command execution raises an error' do
      let(:phase_config) do
        double(
          command: 'nonexistent_command',
          options: [],
          parameter: 'test'
        )
      end

      before do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'handles the exception gracefully' do
        expect(Open3).to receive(:popen3).and_raise(Errno::ENOENT.new('No such file or directory'))

        expect do
          executor.execute(phase: phase_config, issue_number: 123, use_tmux: false)
        end.to raise_error(Soba::Services::WorkflowExecutionError, /Failed to execute workflow command/)
      end
    end
  end

  describe '#build_command' do
    let(:phase_config) do
      double(
        command: 'claude',
        options: ['--dangerous', '--skip-check'],
        parameter: '/osoba:plan {{issue-number}}'
      )
    end

    it 'builds command array correctly' do
      command = executor.send(:build_command, phase_config, 42)

      expect(command).to eq(['claude', '--dangerous', '--skip-check', '/osoba:plan 42'])
    end

    it 'handles nil parameter' do
      config = double(command: 'ls', options: ['-la'], parameter: nil)

      command = executor.send(:build_command, config, 123)

      expect(command).to eq(['ls', '-la'])
    end

    it 'handles multiple placeholders' do
      config = double(
        command: 'echo',
        options: [],
        parameter: 'Issue {{issue-number}} - Number: {{issue-number}}'
      )

      command = executor.send(:build_command, config, 999)

      expect(command).to eq(['echo', 'Issue 999 - Number: 999'])
    end
  end

  describe '#build_command_string' do
    context 'when parameters need quoting' do
      let(:phase_config) do
        double(
          command: 'claude',
          options: ['--dangerously-skip-permissions'],
          parameter: '/soba:plan {{issue-number}}'
        )
      end

      it 'quotes the parameter when building command string' do
        command_string = executor.send(:build_command_string, phase_config, 39)

        expect(command_string).to eq('claude --dangerously-skip-permissions "/soba:plan 39"')
      end
    end

    context 'when building command with worktree' do
      let(:phase_config) do
        double(
          command: 'claude',
          options: [],
          parameter: '/soba:plan {{issue-number}}'
        )
      end

      it 'includes cd to worktree before command' do
        allow(git_workspace_manager).to receive(:get_worktree_path).with(39).and_return('.git/soba/worktrees/issue-39')

        command_string = executor.send(:build_command_string_with_worktree, phase_config, 39)

        expect(command_string).to eq('cd .git/soba/worktrees/issue-39 && claude "/soba:plan 39"')
      end

      it 'returns command without cd when worktree is not available' do
        allow(git_workspace_manager).to receive(:get_worktree_path).with(39).and_return(nil)

        command_string = executor.send(:build_command_string_with_worktree, phase_config, 39)

        expect(command_string).to eq('claude "/soba:plan 39"')
      end
    end
  end

  describe '#execute_direct with worktree' do
    let(:phase_config) do
      double(
        command: 'echo',
        options: [],
        parameter: 'test {{issue-number}}'
      )
    end

    context 'when executing in worktree' do
      it 'changes directory to worktree before executing' do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).with(123).and_return('/tmp/worktrees/issue-123')

        expect(Dir).to receive(:chdir).with('/tmp/worktrees/issue-123').and_yield
        expect(Open3).to receive(:popen3).with('echo', 'test 123') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'test 123')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 123, use_tmux: false)

        expect(result).to include(success: true)
      end

      it 'executes in current directory when worktree is not available' do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).with(123).and_return(nil)

        expect(Dir).not_to receive(:chdir)
        expect(Open3).to receive(:popen3).with('echo', 'test 123') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'test 123')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 123, use_tmux: false)

        expect(result).to include(success: true)
      end
    end
  end

  describe '#execute_in_tmux' do
    let(:phase_config) do
      double(
        name: 'planning',
        command: 'claude',
        options: ['code', '--continue'],
        parameter: '/osoba:plan {{issue-number}}'
      )
    end
    let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

    before do
      allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
      allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
    end

    context 'when executing command in tmux' do
      it 'starts a Claude session in tmux' do
        allow(tmux_session_manager).to receive(:find_or_create_repository_session).and_return({
          success: true,
          session_name: 'soba-repo',
          created: false,
        })
        allow(tmux_session_manager).to receive(:create_issue_window).and_return({
          success: true,
          window_name: 'issue-123',
          created: true,
        })
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = executor.execute_in_tmux(phase: phase_config, issue_number: 123)

        expect(result).to include(
          success: true,
          session_name: 'soba-repo',
          window_name: 'issue-123',
          mode: 'tmux'
        )
      end

      it 'handles tmux session creation failure' do
        expect(tmux_session_manager).to receive(:find_or_create_repository_session).and_return({
          success: false,
          error: 'Failed to create repository session',
        })

        result = executor.execute_in_tmux(phase: phase_config, issue_number: 456)

        expect(result).to include(
          success: false,
          error: 'Failed to create repository session'
        )
      end

      it 'falls back to direct execution when tmux is not installed' do
        expect(tmux_session_manager).to receive(:find_or_create_repository_session).
          and_raise(Soba::Infrastructure::TmuxNotInstalled.new('tmux is not installed'))

        expect(Open3).to receive(:popen3).with('claude', 'code', '--continue', '/osoba:plan 789') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute_in_tmux(phase: phase_config, issue_number: 789)

        expect(result).to include(
          success: true,
          output: 'Command output',
          error: '',
          exit_code: 0
        )
        expect(result).not_to have_key(:mode)
      end

      it 'falls back to direct execution on generic tmux errors' do
        expect(tmux_session_manager).to receive(:find_or_create_repository_session).
          and_raise(StandardError.new('Some tmux error'))

        expect(Open3).to receive(:popen3).with('claude', 'code', '--continue', '/osoba:plan 999') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Fallback output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute_in_tmux(phase: phase_config, issue_number: 999)

        expect(result).to include(
          success: true,
          output: 'Fallback output',
          error: '',
          exit_code: 0
        )
      end
    end

    context 'when phase configuration is nil' do
      let(:phase_config) { double(command: nil, options: nil, parameter: nil) }

      before do
        allow(git_workspace_manager).to receive(:update_main_branch)
        allow(git_workspace_manager).to receive(:setup_workspace)
        allow(git_workspace_manager).to receive(:get_worktree_path).and_return(nil)
      end

      it 'returns nil' do
        result = executor.execute_in_tmux(phase: phase_config, issue_number: 123)

        expect(result).to be_nil
      end
    end
  end
end