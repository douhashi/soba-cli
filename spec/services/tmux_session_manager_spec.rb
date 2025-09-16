# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/tmux_session_manager'
require 'soba/infrastructure/tmux_client'

RSpec.describe Soba::Services::TmuxSessionManager do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:manager) { described_class.new(tmux_client: tmux_client) }

  describe '#start_claude_session' do
    let(:issue_number) { 19 }
    let(:command) { 'claude code --help' }

    context 'when starting a new Claude Code session' do
      context 'with repository configuration' do
        before do
          allow(Soba::Configuration).to receive(:config).and_return(
            double(github: double(repository: 'douhashi/soba'))
          )
        end

        it 'creates a tmux session with repository name in the session name' do
          session_name = nil
          allow(tmux_client).to receive(:session_exists?).and_return(false)
          allow(tmux_client).to receive(:create_session) do |name|
            session_name = name
            true
          end
          allow(tmux_client).to receive(:send_keys).and_return(true)

          result = manager.start_claude_session(issue_number: issue_number, command: command)

          expect(result[:success]).to be true
          expect(result[:session_name]).to match(/^soba-claude-douhashi-soba-19-\d+$/)
          expect(session_name).to eq(result[:session_name])
        end

        it 'converts slashes to hyphens in repository name' do
          allow(Soba::Configuration).to receive(:config).and_return(
            double(github: double(repository: 'owner/repo-name'))
          )
          allow(tmux_client).to receive(:session_exists?).and_return(false)
          allow(tmux_client).to receive(:create_session).and_return(true)
          allow(tmux_client).to receive(:send_keys).and_return(true)

          result = manager.start_claude_session(issue_number: issue_number, command: command)

          expect(result[:success]).to be true
          expect(result[:session_name]).to match(/^soba-claude-owner-repo-name-19-\d+$/)
        end
      end

      context 'without repository configuration' do
        before do
          allow(Soba::Configuration).to receive(:config).and_return(
            double(github: double(repository: nil))
          )
        end

        it 'falls back to original naming convention' do
          session_name = nil
          allow(tmux_client).to receive(:session_exists?).and_return(false)
          allow(tmux_client).to receive(:create_session) do |name|
            session_name = name
            true
          end
          allow(tmux_client).to receive(:send_keys).and_return(true)

          result = manager.start_claude_session(issue_number: issue_number, command: command)

          expect(result[:success]).to be true
          expect(result[:session_name]).to match(/^soba-claude-19-\d+$/)
          expect(session_name).to eq(result[:session_name])
        end
      end

      it 'creates a tmux session with proper naming convention' do
        session_name = nil
        allow(tmux_client).to receive(:session_exists?).and_return(false)
        allow(tmux_client).to receive(:create_session) do |name|
          session_name = name
          true
        end
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = manager.start_claude_session(issue_number: issue_number, command: command)

        expect(result[:success]).to be true
        expect(result[:session_name]).to match(/^soba-claude-([\w-]+-)?19-\d+$/)
        expect(session_name).to eq(result[:session_name])
      end

      it 'sends the command to the tmux session' do
        allow(tmux_client).to receive(:session_exists?).and_return(false)
        allow(tmux_client).to receive(:create_session).and_return(true)
        allow(tmux_client).to receive(:send_keys).and_return(true)

        result = manager.start_claude_session(issue_number: issue_number, command: command)

        expect(tmux_client).to have_received(:send_keys).with(result[:session_name], command)
        expect(result[:success]).to be true
      end

      context 'when session creation fails' do
        it 'returns an error' do
          allow(tmux_client).to receive(:session_exists?).and_return(false)
          allow(tmux_client).to receive(:create_session).and_return(false)

          result = manager.start_claude_session(issue_number: issue_number, command: command)

          expect(result[:success]).to be false
          expect(result[:error]).to match(/Failed to create tmux session/)
        end
      end

      context 'when command sending fails' do
        it 'cleans up the session and returns an error' do
          allow(tmux_client).to receive(:session_exists?).and_return(false)
          allow(tmux_client).to receive(:create_session).and_return(true)
          allow(tmux_client).to receive(:send_keys).and_return(false)
          allow(tmux_client).to receive(:kill_session).and_return(true)

          result = manager.start_claude_session(issue_number: issue_number, command: command)

          expect(result[:success]).to be false
          expect(result[:error]).to match(/Failed to send command/)
          expect(tmux_client).to have_received(:kill_session)
        end
      end
    end
  end

  describe '#stop_claude_session' do
    let(:session_name) { 'soba-claude-19-1234567890' }

    context 'when stopping an existing session' do
      it 'kills the tmux session' do
        allow(tmux_client).to receive(:session_exists?).and_return(true)
        allow(tmux_client).to receive(:kill_session).and_return(true)

        result = manager.stop_claude_session(session_name)

        expect(result[:success]).to be true
        expect(tmux_client).to have_received(:kill_session).with(session_name)
      end

      context 'when session does not exist' do
        it 'returns success with a message' do
          allow(tmux_client).to receive(:session_exists?).and_return(false)

          result = manager.stop_claude_session(session_name)

          expect(result[:success]).to be true
          expect(result[:message]).to match(/Session not found/)
        end
      end

      context 'when kill fails' do
        it 'returns an error' do
          allow(tmux_client).to receive(:session_exists?).and_return(true)
          allow(tmux_client).to receive(:kill_session).and_return(false)

          result = manager.stop_claude_session(session_name)

          expect(result[:success]).to be false
          expect(result[:error]).to match(/Failed to kill session/)
        end
      end
    end
  end

  describe '#get_session_status' do
    let(:session_name) { 'soba-claude-19-1234567890' }

    context 'when checking session status' do
      it 'returns running status for existing session' do
        allow(tmux_client).to receive(:session_exists?).and_return(true)
        allow(tmux_client).to receive(:capture_pane).and_return('$ claude code\nRunning...')

        result = manager.get_session_status(session_name)

        expect(result[:exists]).to be true
        expect(result[:status]).to eq('running')
        expect(result[:last_output]).to include('Running...')
      end

      it 'returns stopped status for non-existing session' do
        allow(tmux_client).to receive(:session_exists?).and_return(false)

        result = manager.get_session_status(session_name)

        expect(result[:exists]).to be false
        expect(result[:status]).to eq('stopped')
        expect(result[:last_output]).to be_nil
      end
    end
  end

  describe '#attach_to_session' do
    let(:session_name) { 'soba-claude-19-1234567890' }

    context 'when attaching to a session' do
      it 'generates the attach command for existing session' do
        allow(tmux_client).to receive(:session_exists?).and_return(true)

        result = manager.attach_to_session(session_name)

        expect(result[:success]).to be true
        expect(result[:command]).to eq("tmux attach-session -t #{session_name}")
      end

      it 'returns error for non-existing session' do
        allow(tmux_client).to receive(:session_exists?).and_return(false)

        result = manager.attach_to_session(session_name)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Session not found/)
      end
    end
  end

  describe '#list_claude_sessions' do
    it 'returns only soba-claude sessions' do
      all_sessions = [
        'soba-claude-19-1234567890',
        'soba-claude-20-0987654321',
        'my-other-session',
        'soba-test-session',
      ]
      allow(tmux_client).to receive(:list_sessions).and_return(all_sessions)

      result = manager.list_claude_sessions

      expect(result).to eq([
        'soba-claude-19-1234567890',
        'soba-claude-20-0987654321',
      ])
    end

    it 'returns empty array when no claude sessions exist' do
      allow(tmux_client).to receive(:list_sessions).and_return(['my-session', 'another-session'])

      result = manager.list_claude_sessions

      expect(result).to eq([])
    end
  end

  describe '#cleanup_old_sessions' do
    it 'removes sessions older than the specified age' do
      # Create session names with timestamps
      now = Time.now.to_i
      old_session = "soba-claude-1-#{now - 7200}" # 2 hours old
      recent_session = "soba-claude-2-#{now - 1800}" # 30 minutes old

      allow(tmux_client).to receive(:list_sessions).and_return([old_session, recent_session])
      allow(tmux_client).to receive(:kill_session).and_return(true)

      result = manager.cleanup_old_sessions(max_age_seconds: 3600) # 1 hour

      expect(result[:cleaned]).to eq([old_session])
      expect(tmux_client).to have_received(:kill_session).with(old_session)
      expect(tmux_client).not_to have_received(:kill_session).with(recent_session)
    end

    it 'handles new session format with repository names' do
      # Create session names with repository names and timestamps
      now = Time.now.to_i
      old_session_with_repo = "soba-claude-owner-repo-1-#{now - 7200}" # 2 hours old
      recent_session_with_repo = "soba-claude-owner-repo-2-#{now - 1800}" # 30 minutes old
      old_session_without_repo = "soba-claude-3-#{now - 7200}" # 2 hours old

      allow(tmux_client).to receive(:list_sessions).and_return([
        old_session_with_repo, recent_session_with_repo, old_session_without_repo,
      ])
      allow(tmux_client).to receive(:kill_session).and_return(true)

      result = manager.cleanup_old_sessions(max_age_seconds: 3600) # 1 hour

      expect(result[:cleaned]).to contain_exactly(old_session_with_repo, old_session_without_repo)
      expect(tmux_client).to have_received(:kill_session).with(old_session_with_repo)
      expect(tmux_client).to have_received(:kill_session).with(old_session_without_repo)
      expect(tmux_client).not_to have_received(:kill_session).with(recent_session_with_repo)
    end
  end
end