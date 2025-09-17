# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/workflow/run'
require 'soba/infrastructure/github_client'
require 'soba/services/issue_watcher'
require 'soba/services/issue_processor'
require 'soba/services/workflow_executor'
require 'soba/services/workflow_blocking_checker'
require 'soba/services/queueing_service'
require 'soba/domain/phase_strategy'
require 'soba/domain/issue'
require 'soba/configuration'

RSpec.describe 'Queueing Workflow Integration' do
  let(:github_client) { double('GitHubClient') }
  let(:command) { Soba::Commands::Workflow::Run.new }
  let(:repository) { 'owner/repo' }

  before do
    allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)

    Soba::Configuration.reset_config
    Soba::Configuration.configure do |c|
      c.github.token = 'test_token'
      c.github.repository = repository
      c.workflow.interval = 10
      c.workflow.use_tmux = false
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
    allow_any_instance_of(Soba::Commands::Workflow::Run).to receive(:sleep) do |instance|
      @execution_count += 1
      instance.instance_variable_set(:@running, false) if @execution_count >= 1
    end

    allow(Signal).to receive(:trap)
  end

  after do
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

      it 'queues the lowest numbered todo issue' do
        # First fetch returns todo issues for checking blocking
        allow(github_client).to receive(:issues).with(repository, state: 'open').
          and_return(todo_issues, todo_issues, [], [])

        # After queueing, fetch returns the updated state
        queued_issue = Soba::Domain::Issue.new(
          number: 10,
          title: 'First Todo',
          labels: [{ name: 'soba:queued' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        allow(github_client).to receive(:issues).and_return(
          todo_issues, # Initial fetch
          [queued_issue] + todo_issues[1..2] # After queueing
        )

        # Process the queued issue
        allow(github_client).to receive(:update_issue_labels).with(
          10, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3).with('echo', 'Plan 10') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Plan executed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        expect { command.execute({}, {}) }.to output(
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

      it 'does not queue new issues while active issue exists' do
        allow(github_client).to receive(:issues).and_return([active_issue, todo_issue])

        # No queueing should happen
        expect(github_client).not_to receive(:update_issue_labels).with(
          15, from: 'soba:todo', to: 'soba:queued'
        )

        # Active issue continues to be processed
        allow(github_client).to receive(:update_issue_labels).with(
          5, from: 'soba:planning', to: 'soba:ready'
        )

        allow(Open3).to receive(:popen3) do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread) if block
        end

        expect { command.execute({}, {}) }.not_to output(/Queued Issue/).to_stdout
      end
    end

    context 'when queued issue transitions through phases' do
      it 'processes queued -> planning -> ready flow' do
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
          50, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3).with('echo', 'Plan 50') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Planning phase completed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        expect { command.execute({}, {}) }.to output(
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

      it 'processes issues in order by issue number' do
        allow(github_client).to receive(:issues).with(repository, state: 'open').
          and_return(todo_issues.reverse) # Return in reverse order

        # Should process issue 10 first (lowest number)
        expect(github_client).to receive(:update_issue_labels).with(
          10, from: 'soba:todo', to: 'soba:queued'
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
          todo_issues.reverse,
          [queued_issue] + remaining_todos
        )

        allow(github_client).to receive(:update_issue_labels).with(
          10, from: 'soba:queued', to: 'soba:planning'
        )

        allow(Open3).to receive(:popen3) do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread) if block
        end

        expect { command.execute({}, {}) }.to output(
          /Queued Issue #10 for processing/
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
        200, from: 'soba:todo', to: 'soba:queued'
      )

      # Continue processing the planning issue
      allow(github_client).to receive(:update_issue_labels).with(
        100, from: 'soba:planning', to: 'soba:ready'
      )

      allow(Open3).to receive(:popen3) do |&block|
        stdin = double('stdin', close: nil)
        stdout = double('stdout', read: '')
        stderr = double('stderr', read: '')
        thread = double('thread', value: double(exitstatus: 0))
        block.call(stdin, stdout, stderr, thread) if block
      end

      command.execute({}, {})
    end
  end
end