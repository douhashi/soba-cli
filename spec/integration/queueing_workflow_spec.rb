# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/start'
require 'soba/infrastructure/github_client'
require 'soba/services/issue_watcher'
require 'soba/services/issue_processor'
require 'soba/services/workflow_executor'
require 'soba/services/workflow_blocking_checker'
require 'soba/services/queueing_service'
require 'soba/services/auto_merge_service'
require 'soba/services/closed_issue_window_cleaner'
require 'soba/domain/phase_strategy'
require 'soba/domain/issue'
require 'soba/configuration'

RSpec.describe 'Queueing Workflow Integration' do
  let(:github_client) { double('GitHubClient') }
  let(:command) { Soba::Commands::Start.new }
  let(:repository) { 'owner/repo' }
  let(:auto_merge_service) { instance_double(Soba::Services::AutoMergeService) }
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:cleaner_service) { instance_double(Soba::Services::ClosedIssueWindowCleaner) }
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'soba.pid') }
  let(:log_file) { File.join(temp_dir, 'daemon.log') }
  let(:status_file) { File.join(temp_dir, 'status.json') }

  before do
    # Mock file paths to use temp directory instead of actual ~/.soba
    allow(File).to receive(:expand_path).and_call_original
    allow(File).to receive(:expand_path).with('~/.soba/soba.pid').and_return(pid_file)
    allow(File).to receive(:expand_path).with('~/.soba/logs/daemon.log').and_return(log_file)
    allow(File).to receive(:expand_path).with('~/.soba/status.json').and_return(status_file)

    allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
    allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
    allow(Soba::Services::AutoMergeService).to receive(:new).and_return(auto_merge_service)
    allow(Soba::Services::ClosedIssueWindowCleaner).to receive(:new).and_return(cleaner_service)
    # Mock tmux client
    allow(tmux_client).to receive(:list_soba_sessions).and_return([])
    # Mock auto-merge service to return no PRs by default
    allow(auto_merge_service).to receive(:execute).and_return(
      merged_count: 0,
      failed_count: 0,
      details: { merged: [], failed: [] }
    )
    # Mock cleaner service to do nothing by default
    allow(cleaner_service).to receive(:should_clean?).and_return(false)
    allow(cleaner_service).to receive(:clean)

    Soba::Configuration.reset_config
    Soba::Configuration.configure do |c|
      c.github.token = 'test_token'
      c.github.repository = repository
      c.workflow.interval = 10
      c.workflow.use_tmux = false
      c.workflow.closed_issue_cleanup_enabled = true
      c.workflow.closed_issue_cleanup_interval = 300
      c.git.setup_workspace = false
      c.phase.plan.command = 'echo'
      c.phase.plan.options = []
      c.phase.plan.parameter = 'Plan {{issue-number}}'
      c.phase.implement.command = 'echo'
      c.phase.implement.options = []
      c.phase.implement.parameter = 'Implement {{issue-number}}'
    end

    allow(Soba::Configuration).to receive(:load!)

    # Mock the infinite loop - run only once
    @execution_count = 0
    allow_any_instance_of(Soba::Commands::Start).to receive(:sleep) do |instance|
      @execution_count += 1
      instance.instance_variable_set(:@running, false) if @execution_count >= 1
    end

    allow(Signal).to receive(:trap)
  end

  after do
    if temp_dir && File.exist?(temp_dir)
      FileUtils.rm_rf(temp_dir)
    end
    Soba::Configuration.reset_config
  end

  describe 'complete queueing workflow' do
    context 'when multiple todo issues exist and no active issues' do
      let(:todo_issues) do
        [
          Soba::Domain::Issue.new(
            number: 10,
            title: 'First Todo',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
          Soba::Domain::Issue.new(
            number: 20,
            title: 'Second Todo',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
          Soba::Domain::Issue.new(
            number: 30,
            title: 'Third Todo',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
        ]
      end

      xit 'queues the lowest numbered todo issue' do
        # After queueing, fetch returns the updated state
        queued_issue = Soba::Domain::Issue.new(
          number: 10,
          title: 'First Todo',
          labels: [{ name: 'soba:queued' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        # Debug: create issues in correct order
        issue10 = todo_issues[0]
        issue20 = todo_issues[1]
        issue30 = todo_issues[2]

        # Debug: Check issue numbers
        expect(issue10.number).to eq(10)
        expect(issue20.number).to eq(20)
        expect(issue30.number).to eq(30)

        # Debug: Check min_by result
        puts "Testing min_by: #{[issue10, issue20, issue30].min_by(&:number).number}"
        puts "Issues order: #{[issue10, issue20, issue30].map(&:number).join(', ')}"

        # Setup mocks for different call patterns
        # Default fallback for any unmatched calls
        allow(github_client).to receive(:issues).and_return([issue10, issue20, issue30])

        # Specific mock for calls with (repository, state: 'open')
        # This will override the default for matching calls
        call_count = 0
        allow(github_client).to receive(:issues).with(repository, state: 'open') do
          call_count += 1
          puts "DEBUG: issues(repository, state: 'open') call ##{call_count}"

          case call_count
          when 1, 2
            # First two calls: return all todo issues
            [issue10, issue20, issue30]
          else
            # After queueing: issue10 is now queued
            [queued_issue, issue20, issue30]
          end
        end

        # Queue the todo issue
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 10, from: 'soba:todo', to: 'soba:queued'
        )

        # Process the queued issue
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 10, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3).with('echo', 'Plan 10') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Plan executed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        # Allow one more loop iteration to process the queued issue
        @execution_count = 0
        allow_any_instance_of(Soba::Commands::Start).to receive(:sleep) do |instance|
          @execution_count += 1
          instance.instance_variable_set(:@running, false) if @execution_count >= 2
        end

        expect { command.execute({}, {}, []) }.to output(
          /✅ Queued Issue #10 for processing.*🚀 Processing Issue #10/m
        ).to_stdout
      end
    end

    context 'when active issue exists' do
      let(:active_issue) do
        Soba::Domain::Issue.new(
          number: 5,
          title: 'Active Issue',
          labels: [{ name: 'soba:planning' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )
      end

      let(:todo_issue) do
        Soba::Domain::Issue.new(
          number: 15,
          title: 'Todo Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )
      end

      xit 'does not queue new issues while active issue exists' do
        allow(github_client).to receive(:issues).and_return([active_issue, todo_issue])

        # No queueing should happen
        expect(github_client).not_to receive(:update_issue_labels).with(
          'owner/repo', 15, from: 'soba:todo', to: 'soba:queued'
        )

        # Active issue continues to be processed
        allow(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 5, from: 'soba:planning', to: 'soba:ready'
        )

        allow(Open3).to receive(:popen3) do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread) if block
        end

        # Ensure the test completes quickly
        command.instance_variable_set(:@running, false)

        expect { command.execute({}, {}, []) }.not_to output(/Queued Issue/).to_stdout
      end
    end

    context 'when queued issue transitions through phases' do
      xit 'processes queued -> planning -> ready flow' do
        # Start with a queued issue
        queued_issue = Soba::Domain::Issue.new(
          number: 50,
          title: 'Queued Issue',
          labels: [{ name: 'soba:queued' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        allow(github_client).to receive(:issues).and_return([queued_issue])

        # Transition from queued to planning
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 50, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3).with('echo', 'Plan 50') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Planning phase completed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        # Ensure the test completes quickly
        command.instance_variable_set(:@running, false)

        expect { command.execute({}, {}, []) }.to output(
          /🚀 Processing Issue #50.*Phase: queued_to_planning/m
        ).to_stdout
      end
    end

    context 'with multiple concurrent todo issues' do
      let(:todo_issues) do
        (1..5).map do |i|
          Soba::Domain::Issue.new(
            number: i * 10,
            title: "Todo Issue #{i}",
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          )
        end
      end

      xit 'processes issues in order by issue number' do
        allow(github_client).to receive(:issues).with(repository, state: 'open').
          and_return(todo_issues.reverse) # Return in reverse order

        # Should process issue 10 first (lowest number)
        expect(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 10, from: 'soba:todo', to: 'soba:queued'
        )

        queued_issue = Soba::Domain::Issue.new(
          number: 10,
          title: 'Todo Issue 1',
          labels: [{ name: 'soba:queued' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        remaining_todos = todo_issues[1..-1]
        allow(github_client).to receive(:issues).and_return(
          todo_issues.reverse, # Initial fetch
          todo_issues.reverse, # Second fetch for queueing check
          [queued_issue] + remaining_todos, # After queueing
          [queued_issue] + remaining_todos # For processing
        )

        allow(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 10, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3) do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread) if block
        end

        # Allow one more loop iteration to process the queued issue
        @execution_count = 0
        allow_any_instance_of(Soba::Commands::Start).to receive(:sleep) do |instance|
          @execution_count += 1
          instance.instance_variable_set(:@running, false) if @execution_count >= 2
        end

        expect { command.execute({}, {}, []) }.to output(
          /✅ Queued Issue #10 for processing/
        ).to_stdout
      end
    end
  end

  describe 'blocking and queueing interactions' do
    it 'respects blocking rules during queueing' do
      planning_issue = Soba::Domain::Issue.new(
        number: 100,
        title: 'Planning Issue',
        labels: [{ name: 'soba:planning' }],
        state: 'open',
        created_at: Time.now.iso8601,
        updated_at: Time.now.iso8601
      )

      todo_issue = Soba::Domain::Issue.new(
        number: 200,
        title: 'Todo Issue',
        labels: [{ name: 'soba:todo' }],
        state: 'open',
        created_at: Time.now.iso8601,
        updated_at: Time.now.iso8601
      )

      allow(github_client).to receive(:issues).and_return([planning_issue, todo_issue])

      # Should not queue because of active issue
      expect(github_client).not_to receive(:update_issue_labels).with(
        'owner/repo', 200, from: 'soba:todo', to: 'soba:queued'
      )

      # Continue processing the planning issue
      allow(github_client).to receive(:update_issue_labels).with(
        'owner/repo', 100, from: 'soba:planning', to: 'soba:ready'
      )

      allow(Open3).to receive(:popen3) do |&block|
        stdin = double('stdin', close: nil)
        stdout = double('stdout', read: '')
        stderr = double('stderr', read: '')
        thread = double('thread', value: double(exitstatus: 0))
        block.call(stdin, stdout, stderr, thread) if block
      end

      command.execute({}, {}, [])
    end

    context 'when active soba label and todo issue exist simultaneously (Issue #99)' do
      it 'does not queue todo issues when intermediate labels exist' do
        review_requested_issue = Soba::Domain::Issue.new(
          number: 101,
          title: 'Review Requested Issue',
          labels: [{ name: 'soba:review-requested' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        todo_issue = Soba::Domain::Issue.new(
          number: 102,
          title: 'Todo Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        allow(github_client).to receive(:issues).and_return([review_requested_issue, todo_issue])

        # Should not queue todo issue because review-requested issue exists
        expect(github_client).not_to receive(:update_issue_labels).with(
          'owner/repo', 102, from: 'soba:todo', to: 'soba:queued'
        )

        command.execute({}, {}, [])
      end

      it 'does not queue todo issues when multiple active labels exist' do
        doing_issue = Soba::Domain::Issue.new(
          number: 103,
          title: 'Doing Issue',
          labels: [{ name: 'soba:doing' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        reviewing_issue = Soba::Domain::Issue.new(
          number: 104,
          title: 'Reviewing Issue',
          labels: [{ name: 'soba:reviewing' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        todo_issue = Soba::Domain::Issue.new(
          number: 105,
          title: 'Todo Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        allow(github_client).to receive(:issues).and_return([doing_issue, reviewing_issue, todo_issue])

        # Should not queue todo issue because active issues exist
        expect(github_client).not_to receive(:update_issue_labels).with(
          'owner/repo', 105, from: 'soba:todo', to: 'soba:queued'
        )

        # Process existing active issues
        allow(github_client).to receive(:update_issue_labels).with(
          'owner/repo', 103, from: 'soba:doing', to: 'soba:reviewing'
        )

        allow(Open3).to receive(:popen3) do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread) if block
        end

        command.execute({}, {}, [])
      end
    end
  end
end