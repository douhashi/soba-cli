# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/closed_issue_window_cleaner'

RSpec.describe Soba::Services::ClosedIssueWindowCleaner do
  let(:github_client) { instance_double('Soba::Infrastructure::GitHubClient') }
  let(:tmux_client) { instance_double('Soba::Infrastructure::TmuxClient') }
  let(:logger) { instance_double('Soba::Logger', info: nil, debug: nil, warn: nil, error: nil) }
  let(:cleaner) { described_class.new(github_client: github_client, tmux_client: tmux_client, logger: logger) }

  describe '#clean' do
    let(:session_name) { 'soba-workflow' }

    before do
      # Mock the configuration for all tests
      allow(Soba::Configuration).to receive(:config).and_return(
        double('Config',
          github: double('GithubConfig', repository: 'test/repo'),
          workflow: double('WorkflowConfig',
            closed_issue_cleanup_enabled: true,
            closed_issue_cleanup_interval: 300))
      )
    end

    context 'when there are closed issues with corresponding tmux windows' do
      let(:closed_issues) do
        [
          double('Issue', number: 42, title: 'Fix bug', state: 'closed'),
          double('Issue', number: 43, title: 'Add feature', state: 'closed'),
          double('Issue', number: 44, title: 'Update docs', state: 'closed'),
        ]
      end

      let(:tmux_windows) { ['issue-42', 'issue-43', 'issue-45', 'other-window'] }

      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_return(closed_issues)
        allow(tmux_client).to receive(:list_windows).with(session_name).and_return(tmux_windows)
        allow(tmux_client).to receive(:kill_window).and_return(true)
      end

      it 'removes windows for closed issues' do
        cleaner.clean(session_name)

        expect(tmux_client).to have_received(:kill_window).with(session_name, 'issue-42')
        expect(tmux_client).to have_received(:kill_window).with(session_name, 'issue-43')
        expect(tmux_client).not_to have_received(:kill_window).with(session_name, 'issue-44')
        expect(tmux_client).not_to have_received(:kill_window).with(session_name, 'issue-45')
        expect(tmux_client).not_to have_received(:kill_window).with(session_name, 'other-window')
      end

      it 'logs the cleanup actions' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:info).with('Cleaning up windows for closed issues...')
        expect(logger).to have_received(:info).with('Found 3 closed issues')
        expect(logger).to have_received(:info).with('Removed window: issue-42 (Issue #42: Fix bug)')
        expect(logger).to have_received(:info).with('Removed window: issue-43 (Issue #43: Add feature)')
        expect(logger).to have_received(:info).with('Cleanup completed: removed 2 windows')
      end
    end

    context 'when there are no closed issues' do
      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_return([])
        allow(tmux_client).to receive(:list_windows).with(session_name).and_return(['issue-42'])
        allow(tmux_client).to receive(:kill_window).and_return(true)
      end

      it 'does not remove any windows' do
        cleaner.clean(session_name)

        expect(tmux_client).not_to have_received(:kill_window)
      end

      it 'logs that no cleanup is needed' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:info).with('Cleaning up windows for closed issues...')
        expect(logger).to have_received(:info).with('No closed issues found')
      end
    end

    context 'when there are no tmux windows matching closed issues' do
      let(:closed_issues) do
        [double('Issue', number: 42, title: 'Fix bug', state: 'closed')]
      end

      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_return(closed_issues)
        allow(tmux_client).to receive(:list_windows).with(session_name).and_return(['other-window'])
        allow(tmux_client).to receive(:kill_window).and_return(true)
      end

      it 'does not remove any windows' do
        cleaner.clean(session_name)

        expect(tmux_client).not_to have_received(:kill_window)
      end

      it 'logs that no windows need cleanup' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:info).with('Cleaning up windows for closed issues...')
        expect(logger).to have_received(:info).with('Found 1 closed issues')
        expect(logger).to have_received(:info).with('Cleanup completed: removed 0 windows')
      end
    end

    context 'when tmux window removal fails' do
      let(:closed_issues) do
        [double('Issue', number: 42, title: 'Fix bug', state: 'closed')]
      end

      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_return(closed_issues)
        allow(tmux_client).to receive(:list_windows).with(session_name).and_return(['issue-42'])
        allow(tmux_client).to receive(:kill_window).with(session_name, 'issue-42').and_return(false)
      end

      it 'logs a warning but continues' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:warn).with('Failed to remove window: issue-42')
        expect(logger).to have_received(:info).with('Cleanup completed: removed 0 windows')
      end
    end

    context 'when GitHub API call fails' do
      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_raise(StandardError.new('API error'))
        allow(tmux_client).to receive(:kill_window).and_return(true)
      end

      it 'logs the error and does not crash' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:error).with('Failed to fetch closed issues: API error')
        expect(tmux_client).not_to have_received(:kill_window)
      end
    end

    context 'when tmux list_windows fails' do
      let(:closed_issues) do
        [double('Issue', number: 42, title: 'Fix bug', state: 'closed')]
      end

      before do
        allow(github_client).to receive(:fetch_closed_issues).with('test/repo').and_return(closed_issues)
        allow(tmux_client).to receive(:list_windows).with(session_name).and_raise(StandardError.new('tmux error'))
        allow(tmux_client).to receive(:kill_window).and_return(true)
      end

      it 'logs the error and does not crash' do
        cleaner.clean(session_name)

        expect(logger).to have_received(:error).with('Failed to list tmux windows: tmux error')
        expect(tmux_client).not_to have_received(:kill_window)
      end
    end
  end

  describe '#should_clean?' do
    before do
      # Mock the configuration properly
      allow(Soba::Configuration).to receive(:config).and_return(
        double('Config',
          workflow: double('WorkflowConfig',
            closed_issue_cleanup_enabled: true,
            closed_issue_cleanup_interval: 300))
      )
    end

    context 'when cleanup is enabled and interval has passed' do
      it 'returns true on first call' do
        expect(cleaner.should_clean?).to be true
      end

      it 'returns false immediately after cleaning' do
        cleaner.should_clean?
        expect(cleaner.should_clean?).to be false
      end

      it 'returns true after interval has passed' do
        # First call to initialize
        cleaner.should_clean?

        # Mock time advance
        allow(Time).to receive(:now).and_return(Time.now + 301)
        expect(cleaner.should_clean?).to be true
      end
    end

    context 'when cleanup is disabled' do
      before do
        allow(Soba::Configuration).to receive(:config).and_return(
          double('Config',
            workflow: double('WorkflowConfig',
              closed_issue_cleanup_enabled: false,
              closed_issue_cleanup_interval: 300))
        )
      end

      it 'always returns false' do
        expect(cleaner.should_clean?).to be false
      end
    end
  end
end