# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/open'

RSpec.describe Soba::Commands::Open do
  let(:command) { described_class.new }
  let(:repository_path) { '/path/to/repo' }
  let(:issue_number) { '74' }

  before do
    allow(Soba::Configuration).to receive(:load!)
    config = instance_double('Config')
    github_config = instance_double('GithubConfig')
    allow(github_config).to receive(:repository).and_return('test-repo')
    allow(config).to receive(:github).and_return(github_config)
    allow(Soba::Configuration).to receive(:config).and_return(config)
  end

  describe '#execute' do
    context 'when issue number is provided' do
      let(:tmux_session_manager) { instance_double(Soba::Services::TmuxSessionManager) }
      let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

      before do
        allow(Soba::Services::TmuxSessionManager).to receive(:new).and_return(tmux_session_manager)
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
      end

      context 'when session/window exists' do
        before do
          allow(tmux_client).to receive(:tmux_installed?).and_return(true)
          allow(tmux_session_manager).to receive(:find_issue_window).
            with('test-repo', issue_number).
            and_return('soba-test-repo:issue-74')
        end

        it 'attaches to the tmux session' do
          expect(tmux_client).to receive(:attach_to_window).with('soba-test-repo:issue-74')
          command.execute(issue_number)
        end

        it 'outputs success message' do
          allow(tmux_client).to receive(:attach_to_window)
          expect { command.execute(issue_number) }.
            to output(/Issue #74 のセッションにアタッチします/).to_stdout
        end
      end

      context 'when session/window does not exist' do
        before do
          allow(tmux_client).to receive(:tmux_installed?).and_return(true)
          allow(tmux_session_manager).to receive(:find_issue_window).
            with('test-repo', issue_number).
            and_return(nil)
        end

        it 'raises an error with helpful message' do
          expect { command.execute(issue_number) }.to raise_error(
            Soba::Commands::Open::SessionNotFoundError,
            /Issue #74 のセッションが見つかりません/
          )
        end
      end
    end

    context 'when --list option is provided' do
      let(:tmux_session_manager) { instance_double(Soba::Services::TmuxSessionManager) }

      before do
        allow(Soba::Services::TmuxSessionManager).to receive(:new).and_return(tmux_session_manager)
      end

      it 'lists active issue sessions' do
        sessions = [
          { window: 'issue-74', title: 'soba open コマンドの作成' },
          { window: 'issue-73', title: 'workflow run コマンドの実装' },
        ]

        allow(tmux_session_manager).to receive(:list_issue_windows).
          with('test-repo').
          and_return(sessions)

        expect { command.execute(nil, list: true) }.
          to output(/アクティブなIssueセッション/).to_stdout
        expect { command.execute(nil, list: true) }.
          to output(/74.*soba open コマンドの作成/).to_stdout
        expect { command.execute(nil, list: true) }.
          to output(/73.*workflow run コマンドの実装/).to_stdout
      end

      it 'shows message when no sessions are active' do
        allow(tmux_session_manager).to receive(:list_issue_windows).
          with('test-repo').
          and_return([])

        expect { command.execute(nil, list: true) }.
          to output(/アクティブなIssueセッションがありません/).to_stdout
      end
    end

    context 'when tmux is not installed' do
      let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

      before do
        allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
        allow(tmux_client).to receive(:tmux_installed?).and_return(false)
      end

      it 'raises TmuxNotInstalledError' do
        expect { command.execute(issue_number) }.to raise_error(
          Soba::Infrastructure::TmuxNotInstalled,
          /tmuxがインストールされていません/
        )
      end
    end

    context 'when no issue number is provided and no --list option' do
      it 'raises an error' do
        expect { command.execute(nil) }.to raise_error(
          ArgumentError,
          /Issue番号を指定するか、--listオプションを使用してください/
        )
      end
    end
  end
end