# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/tmux_session_manager'
require 'soba/infrastructure/tmux_client'
require 'soba/infrastructure/lock_manager'

RSpec.describe Soba::Services::TmuxSessionManager do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:lock_manager) { instance_double(Soba::Infrastructure::LockManager) }
  let(:test_process_manager) { instance_double(Soba::Services::TestProcessManager) }
  let(:manager) { described_class.new(tmux_client: tmux_client, lock_manager: lock_manager, test_process_manager: test_process_manager) }

  describe '#find_or_create_repository_session' do
    before do
      allow(Soba::Configuration).to receive(:config).and_return(
        double(github: double(repository: 'owner/repo-name'))
      )
      allow(Process).to receive(:pid).and_return(12345)
      allow(test_process_manager).to receive(:test_mode?).and_return(false)
    end

    it 'creates a new repository session with PID if not exists' do
      session_name = 'soba-owner-repo-name-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)
      allow(tmux_client).to receive(:create_session).with(session_name).and_return(true)

      result = manager.find_or_create_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
      expect(result[:created]).to be true
      expect(tmux_client).to have_received(:create_session).with(session_name)
    end

    it 'returns existing repository session if exists' do
      session_name = 'soba-owner-repo-name-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
      allow(tmux_client).to receive(:create_session)

      result = manager.find_or_create_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
      expect(result[:created]).to be false
      expect(tmux_client).not_to have_received(:create_session)
    end

    it 'handles repository names with special characters' do
      allow(Soba::Configuration).to receive(:config).and_return(
        double(github: double(repository: 'owner/repo.name-with_special'))
      )
      session_name = 'soba-owner-repo-name-with-special-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)
      allow(tmux_client).to receive(:create_session).with(session_name).and_return(true)

      result = manager.find_or_create_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
    end

    context 'when repository configuration is missing' do
      before do
        allow(Soba::Configuration).to receive(:config).and_return(
          double(github: double(repository: nil))
        )
      end

      it 'returns an error' do
        result = manager.find_or_create_repository_session

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Repository configuration not found/)
      end
    end

    context 'when in test mode' do
      before do
        allow(test_process_manager).to receive(:test_mode?).and_return(true)
        allow(test_process_manager).to receive(:generate_test_session_name)
          .with('owner/repo-name')
          .and_return('soba-test-owner-repo-name-12345-abcd1234')
      end

      it 'creates test session with test prefix' do
        session_name = 'soba-test-owner-repo-name-12345-abcd1234'
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)
        allow(tmux_client).to receive(:create_session).with(session_name).and_return(true)

        result = manager.find_or_create_repository_session

        expect(result[:success]).to be true
        expect(result[:session_name]).to eq(session_name)
        expect(result[:created]).to be true
        expect(tmux_client).to have_received(:create_session).with(session_name)
      end

      it 'returns existing test session if exists' do
        session_name = 'soba-test-owner-repo-name-12345-abcd1234'
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)

        result = manager.find_or_create_repository_session

        expect(result[:success]).to be true
        expect(result[:session_name]).to eq(session_name)
        expect(result[:created]).to be false
      end
    end
  end

  describe '#create_issue_window' do
    let(:session_name) { 'soba-owner-repo-12345' }
    let(:issue_number) { 42 }

    before do
      allow(lock_manager).to receive(:with_lock).and_yield
    end

    it 'creates a new window for the issue' do
      window_name = 'issue-42'
      allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(false, true)
      allow(tmux_client).to receive(:create_window).with(session_name, window_name).and_return(true)

      result = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

      expect(result[:success]).to be true
      expect(result[:window_name]).to eq(window_name)
      expect(result[:created]).to be true
      expect(tmux_client).to have_received(:create_window).with(session_name, window_name)
    end

    it 'returns existing window if already exists' do
      window_name = 'issue-42'
      allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
      allow(tmux_client).to receive(:create_window)

      result = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

      expect(result[:success]).to be true
      expect(result[:window_name]).to eq(window_name)
      expect(result[:created]).to be false
      expect(tmux_client).not_to have_received(:create_window)
    end

    context 'when multiple calls for the same issue' do
      it 'always returns the same window' do
        window_name = 'issue-42'
        # First call creates the window
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(false, true)
        allow(tmux_client).to receive(:create_window).with(session_name, window_name).and_return(true)

        result1 = manager.create_issue_window(session_name: session_name, issue_number: issue_number)
        result2 = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

        expect(result1[:success]).to be true
        expect(result1[:created]).to be true
        expect(result2[:success]).to be true
        expect(result2[:created]).to be false
        expect(result1[:window_name]).to eq(result2[:window_name])
        expect(tmux_client).to have_received(:create_window).once
      end
    end

    context 'when duplicate windows exist' do
      it 'detects and uses existing window instead of creating another' do
        window_name = 'issue-58'
        # Simulating the duplicate window case from the issue
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:create_window)

        result = manager.create_issue_window(session_name: session_name, issue_number: 58)

        expect(result[:success]).to be true
        expect(result[:window_name]).to eq(window_name)
        expect(result[:created]).to be false
        expect(tmux_client).not_to have_received(:create_window)
      end
    end

    context 'when window creation fails' do
      it 'returns an error' do
        window_name = 'issue-42'
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(false)
        allow(tmux_client).to receive(:create_window).with(session_name, window_name).and_return(false)

        result = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Failed to create window/)
      end
    end

    context 'when lock acquisition fails' do
      it 'returns an error with lock failure message' do
        allow(lock_manager).to receive(:with_lock).and_raise(
          Soba::Infrastructure::LockTimeoutError, 'Failed to acquire lock'
        )

        result = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Lock acquisition failed/)
      end
    end

    context 'with concurrent window creation attempts' do
      it 'ensures only one window is created' do
        window_name = 'issue-42'
        creation_count = 0

        allow(lock_manager).to receive(:with_lock) do |&block|
          block.call
        end

        # Simulate concurrent attempts
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name) do
          !(creation_count == 0)
        end

        allow(tmux_client).to receive(:create_window).with(session_name, window_name) do
          creation_count += 1
          true
        end

        result1 = manager.create_issue_window(session_name: session_name, issue_number: issue_number)
        result2 = manager.create_issue_window(session_name: session_name, issue_number: issue_number)

        expect(creation_count).to eq(1)
        expect(result1[:created]).to be true
        expect(result2[:created]).to be false
      end
    end
  end

  describe '#find_repository_session' do
    before do
      allow(Soba::Configuration).to receive(:config).and_return(
        double(github: double(repository: 'owner/repo-name'))
      )
      allow(Process).to receive(:pid).and_return(12345)
      allow(test_process_manager).to receive(:test_mode?).and_return(false)
    end

    it 'returns session name when repository session exists' do
      session_name = 'soba-owner-repo-name-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)

      result = manager.find_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
      expect(result[:exists]).to be true
    end

    it 'returns not exists when repository session does not exist' do
      session_name = 'soba-owner-repo-name-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)

      result = manager.find_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
      expect(result[:exists]).to be false
    end

    it 'handles repository names with special characters' do
      allow(Soba::Configuration).to receive(:config).and_return(
        double(github: double(repository: 'owner/repo.name-with_special'))
      )
      session_name = 'soba-owner-repo-name-with-special-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)

      result = manager.find_repository_session

      expect(result[:success]).to be true
      expect(result[:session_name]).to eq(session_name)
      expect(result[:exists]).to be true
    end

    context 'when repository configuration is missing' do
      before do
        allow(Soba::Configuration).to receive(:config).and_return(
          double(github: double(repository: nil))
        )
      end

      it 'returns an error' do
        result = manager.find_repository_session

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Repository configuration not found/)
      end
    end
  end

  describe '#create_phase_pane' do
    let(:session_name) { 'soba-owner-repo-12345' }
    let(:window_name) { 'issue-42' }
    let(:phase) { 'planning' }

    context 'with prerequisite checks' do
      it 'verifies session exists before creating pane' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)
        allow(tmux_client).to receive(:split_window)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Session does not exist')
        expect(tmux_client).not_to have_received(:split_window)
      end

      it 'verifies window exists before creating pane' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(false)
        allow(tmux_client).to receive(:split_window)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Window does not exist')
        expect(tmux_client).not_to have_received(:split_window)
      end

      it 'checks tmux server responsiveness' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(nil) # tmuxサーバーが応答しない
        allow(tmux_client).to receive(:split_window)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('tmux server is not responding')
        expect(tmux_client).not_to have_received(:split_window)
      end
    end

    it 'creates a new pane for the phase' do
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
      allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
      allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
      allow(tmux_client).to receive(:list_panes).and_return([])
      allow(tmux_client).to receive(:split_window).with(
        session_name: session_name,
        window_name: window_name,
        vertical: true
      ).and_return('%0')
      allow(tmux_client).to receive(:select_layout).and_return(true)

      result = manager.create_phase_pane(
        session_name: session_name,
        window_name: window_name,
        phase: phase
      )

      expect(result[:success]).to be true
      expect(result[:pane_id]).to eq('%0')
      expect(result[:phase]).to eq(phase)
    end

    it 'supports horizontal splitting' do
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
      allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
      allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
      allow(tmux_client).to receive(:list_panes).and_return([])
      allow(tmux_client).to receive(:split_window).with(
        session_name: session_name,
        window_name: window_name,
        vertical: false
      ).and_return('%1')
      allow(tmux_client).to receive(:select_layout).and_return(true)

      result = manager.create_phase_pane(
        session_name: session_name,
        window_name: window_name,
        phase: phase,
        vertical: false
      )

      expect(result[:success]).to be true
      expect(result[:pane_id]).to eq('%1')
    end

    context 'when there are 3 or more existing panes' do
      it 'removes the oldest pane before creating a new one' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
        # 3つのペインが既に存在
        existing_panes = [
          { id: '%0', start_time: 1734444000 }, # oldest
          { id: '%1', start_time: 1734444100 },
          { id: '%2', start_time: 1734444200 },
        ]
        allow(tmux_client).to receive(:list_panes).and_return(existing_panes)
        allow(tmux_client).to receive(:kill_pane).with('%0').and_return(true)
        allow(tmux_client).to receive(:split_window).and_return('%3')
        allow(tmux_client).to receive(:select_layout).and_return(true)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(tmux_client).to have_received(:kill_pane).with('%0')
        expect(result[:success]).to be true
        expect(result[:pane_id]).to eq('%3')
      end

      it 'maintains exactly 3 panes when adding a 4th' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
        # 4つのペインが既に存在
        existing_panes = [
          { id: '%0', start_time: 1734444000 }, # oldest
          { id: '%1', start_time: 1734444100 }, # second oldest
          { id: '%2', start_time: 1734444200 },
          { id: '%3', start_time: 1734444300 },
        ]
        allow(tmux_client).to receive(:list_panes).and_return(existing_panes)
        # 最も古い2つのペインを削除
        allow(tmux_client).to receive(:kill_pane).with('%0').and_return(true)
        allow(tmux_client).to receive(:kill_pane).with('%1').and_return(true)
        allow(tmux_client).to receive(:split_window).and_return('%4')
        allow(tmux_client).to receive(:select_layout).and_return(true)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(tmux_client).to have_received(:kill_pane).with('%0')
        expect(tmux_client).to have_received(:kill_pane).with('%1')
        expect(result[:success]).to be true
      end
    end

    context 'when layout adjustment is needed' do
      it 'applies even-horizontal layout after creating pane' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
        allow(tmux_client).to receive(:list_panes).and_return([])
        allow(tmux_client).to receive(:split_window).and_return('%0')
        allow(tmux_client).to receive(:select_layout).with(
          session_name, window_name, 'even-horizontal'
        ).and_return(true)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(tmux_client).to have_received(:select_layout).with(
          session_name, window_name, 'even-horizontal'
        )
        expect(result[:success]).to be true
      end
    end

    context 'when pane creation fails' do
      it 'returns an error' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
        allow(tmux_client).to receive(:list_panes).and_return([])
        allow(tmux_client).to receive(:split_window).and_return(nil)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Failed to create pane/)
      end

      context 'with retry mechanism' do
        it 'retries on temporary failures and succeeds' do
          allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
          allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
          allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
          allow(tmux_client).to receive(:list_panes).and_return([])
          call_count = 0
          allow(tmux_client).to receive(:split_window) do
            call_count += 1
            if call_count < 3
              [nil, { stderr: 'temporary error', exit_status: 1 }]
            else
              '%3'
            end
          end
          allow(tmux_client).to receive(:select_layout).and_return(true)
          allow(manager).to receive(:sleep) # スリープをスタブ化

          result = manager.create_phase_pane(
            session_name: session_name,
            window_name: window_name,
            phase: phase
          )

          expect(result[:success]).to be true
          expect(result[:pane_id]).to eq('%3')
          expect(tmux_client).to have_received(:split_window).exactly(3).times
        end

        it 'fails after maximum retry attempts' do
          allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
          allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
          allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
          allow(tmux_client).to receive(:list_panes).and_return([])
          allow(tmux_client).to receive(:split_window).and_return(
            [nil, { stderr: 'permanent error', exit_status: 1 }]
          )
          allow(manager).to receive(:sleep) # スリープをスタブ化

          result = manager.create_phase_pane(
            session_name: session_name,
            window_name: window_name,
            phase: phase
          )

          expect(result[:success]).to be false
          expect(result[:error]).to include('Failed to create pane')
          expect(result[:error]).to include('permanent error')
          expect(tmux_client).to have_received(:split_window).exactly(3).times
        end

        it 'logs error details for each retry' do
          allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
          allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
          allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
          allow(tmux_client).to receive(:list_panes).and_return([])
          allow(tmux_client).to receive(:split_window).and_return(
            [nil, { stderr: 'detailed error message', exit_status: 1 }]
          )
          allow(manager).to receive(:sleep)

          # ログ出力をキャプチャ
          allow(Soba.logger).to receive(:warn)
          allow(Soba.logger).to receive(:error)

          manager.create_phase_pane(
            session_name: session_name,
            window_name: window_name,
            phase: phase
          )

          expect(Soba.logger).to have_received(:warn).at_least(2).times
          expect(Soba.logger).to have_received(:error).once
        end
      end
    end

    context 'when pane cleanup fails' do
      it 'continues with pane creation' do
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        allow(tmux_client).to receive(:window_exists?).with(session_name, window_name).and_return(true)
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test'])
        existing_panes = [
          { id: '%0', start_time: 1734444000 },
          { id: '%1', start_time: 1734444100 },
          { id: '%2', start_time: 1734444200 },
        ]
        allow(tmux_client).to receive(:list_panes).and_return(existing_panes)
        allow(tmux_client).to receive(:kill_pane).with('%0').and_return(false) # 削除失敗
        allow(tmux_client).to receive(:split_window).and_return('%3')
        allow(tmux_client).to receive(:select_layout).and_return(true)

        result = manager.create_phase_pane(
          session_name: session_name,
          window_name: window_name,
          phase: phase
        )

        expect(tmux_client).to have_received(:kill_pane).with('%0')
        expect(result[:success]).to be true
        expect(result[:pane_id]).to eq('%3')
      end
    end
  end

  describe '#session_exists?' do
    it 'returns true when session exists' do
      session_name = 'soba-test-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)

      expect(manager.session_exists?(session_name)).to be true
    end

    it 'returns false when session does not exist' do
      session_name = 'soba-test-12345'
      allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)

      expect(manager.session_exists?(session_name)).to be false
    end
  end

  describe '#find_repository_session_by_pid' do
    let(:repository) { 'owner/repo' }
    let(:pid_manager) { instance_double(Soba::Services::PidManager) }

    before do
      allow(Soba::Services::PidManager).to receive(:new).and_return(pid_manager)
    end

    context 'when PID file exists and session exists' do
      it 'returns the session name' do
        pid = 12345
        session_name = 'soba-owner-repo-12345'

        allow(pid_manager).to receive(:read).and_return(pid)
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)

        result = manager.find_repository_session_by_pid(repository)

        expect(result[:success]).to be true
        expect(result[:session_name]).to eq(session_name)
        expect(result[:exists]).to be true
      end
    end

    context 'when PID file exists but session does not exist' do
      it 'returns exists: false and cleans up PID file' do
        pid = 12345
        session_name = 'soba-owner-repo-12345'

        allow(pid_manager).to receive(:read).and_return(pid)
        allow(pid_manager).to receive(:delete).and_return(true)
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)

        result = manager.find_repository_session_by_pid(repository)

        expect(result[:success]).to be true
        expect(result[:session_name]).to be_nil
        expect(result[:exists]).to be false
        expect(pid_manager).to have_received(:delete)
      end
    end

    context 'when PID file does not exist' do
      it 'returns exists: false' do
        allow(pid_manager).to receive(:read).and_return(nil)

        result = manager.find_repository_session_by_pid(repository)

        expect(result[:success]).to be true
        expect(result[:session_name]).to be_nil
        expect(result[:exists]).to be false
      end
    end
  end
end