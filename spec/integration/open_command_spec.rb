# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/open'
require 'soba/infrastructure/tmux_client'

RSpec.describe 'Open command integration', type: :integration do
  let(:tmux_client) { Soba::Infrastructure::TmuxClient.new }
  let(:repository_name) { 'test-repo' }
  let(:session_name) { "soba-#{repository_name}" }
  let(:issue_number) { '74' }
  let(:window_name) { "issue-#{issue_number}" }

  before do
    # Clean up any existing sessions
    tmux_client.kill_session(session_name) if tmux_client.session_exists?(session_name)
  end

  after do
    # Clean up test sessions
    tmux_client.kill_session(session_name) if tmux_client.session_exists?(session_name)
  end

  describe 'opening an issue session' do
    context 'when the session and window exist' do
      before do
        # Create a test session and window
        tmux_client.create_session(session_name)
        tmux_client.create_window(session_name, window_name)
      end

      it 'successfully identifies the existing window' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        window_id = tmux_session_manager.find_issue_window(repository_name, issue_number)

        expect(window_id).to eq("#{session_name}:#{window_name}")
      end
    end

    context 'when the session exists but window does not' do
      before do
        # Create only the session, not the window
        tmux_client.create_session(session_name)
      end

      it 'returns nil for non-existent window' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        window_id = tmux_session_manager.find_issue_window(repository_name, issue_number)

        expect(window_id).to be_nil
      end
    end

    context 'when neither session nor window exist' do
      it 'returns nil' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        window_id = tmux_session_manager.find_issue_window(repository_name, issue_number)

        expect(window_id).to be_nil
      end
    end
  end

  describe 'listing issue sessions' do
    context 'when multiple issue windows exist' do
      before do
        tmux_client.create_session(session_name)
        tmux_client.create_window(session_name, 'issue-74')
        tmux_client.create_window(session_name, 'issue-73')
        tmux_client.create_window(session_name, 'non-issue-window')
      end

      it 'lists only issue windows' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        sessions = tmux_session_manager.list_issue_windows(repository_name)

        expect(sessions.size).to eq(2)
        expect(sessions.map { |s| s[:window] }).to contain_exactly('issue-74', 'issue-73')
      end
    end

    context 'when no issue windows exist' do
      before do
        tmux_client.create_session(session_name)
        tmux_client.create_window(session_name, 'main-window')
      end

      it 'returns empty array' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        sessions = tmux_session_manager.list_issue_windows(repository_name)

        expect(sessions).to eq([])
      end
    end

    context 'when session does not exist' do
      it 'returns empty array' do
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(config: nil, tmux_client: tmux_client)
        sessions = tmux_session_manager.list_issue_windows(repository_name)

        expect(sessions).to eq([])
      end
    end
  end
end