# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/workflow/run'
require 'soba/infrastructure/github_client'
require 'soba/services/issue_watcher'
require 'soba/services/issue_processor'
require 'soba/services/workflow_executor'
require 'soba/domain/phase_strategy'
require 'soba/domain/issue'
require 'soba/configuration'

RSpec.describe Soba::Commands::Workflow::Run do
  let(:command) { described_class.new }
  let(:github_client) { double('GitHubClient') }

  before do
    allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)

    Soba::Configuration.reset_config
    Soba::Configuration.configure do |c|
      c.github.token = 'test_token'
      c.github.repository = 'owner/repo'
      c.workflow.interval = 10
      c.workflow.use_tmux = false # Disable tmux for tests
      c.phase.plan.command = 'echo'
      c.phase.plan.options = []
      c.phase.plan.parameter = 'Plan {{issue-number}}'
      c.phase.implement.command = 'echo'
      c.phase.implement.options = []
      c.phase.implement.parameter = 'Implement {{issue-number}}'
    end

    # Skip Configuration.load! in tests
    allow(Soba::Configuration).to receive(:load!)

    # Mock the infinite loop - run only once
    @execution_count = 0
    allow_any_instance_of(described_class).to receive(:sleep) do |instance|
      @execution_count += 1
      instance.instance_variable_set(:@running, false) if @execution_count >= 1
    end

    allow(Signal).to receive(:trap)
  end

  after do
    Soba::Configuration.reset_config
  end

  describe '#execute' do
    context 'when workflow processes issues with soba:todo label' do
      let(:issues_with_todo) do
        [
          Soba::Domain::Issue.new(
            number: 1,
            title: 'Issue 1',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
        ]
      end

      before do
        allow(github_client).to receive(:issues).and_return(issues_with_todo)
      end

      it 'updates label and executes workflow' do
        expect(github_client).to receive(:update_issue_labels).with(1, from: 'soba:todo', to: 'soba:planning')

        allow(Open3).to receive(:popen3).with('echo', 'Plan 1') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Plan executed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        expect { command.execute({}, {}) }.to output(/Processing Issue #1/).to_stdout
      end
    end

    context 'when workflow processes issues with soba:ready label' do
      let(:issues_with_ready) do
        [
          Soba::Domain::Issue.new(
            number: 3,
            title: 'Issue 3',
            labels: [{ name: 'soba:ready' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
        ]
      end

      before do
        allow(github_client).to receive(:issues).and_return(issues_with_ready)
      end

      it 'updates label and executes workflow' do
        expect(github_client).to receive(:update_issue_labels).with(3, from: 'soba:ready', to: 'soba:doing')

        allow(Open3).to receive(:popen3).with('echo', 'Implement 3') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Implementation started')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        expect { command.execute({}, {}) }.to output(/Processing Issue #3/).to_stdout
      end
    end

    context 'when issues are already in progress' do
      let(:issues_in_progress) do
        [
          Soba::Domain::Issue.new(
            number: 4,
            title: 'Issue 4',
            labels: ['soba:planning'],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
          Soba::Domain::Issue.new(
            number: 5,
            title: 'Issue 5',
            labels: [{ name: 'soba:doing' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
        ]
      end

      before do
        allow(github_client).to receive(:issues).and_return(issues_in_progress)
      end

      it 'skips processing' do
        expect(github_client).not_to receive(:update_issue_labels)
        expect(Open3).not_to receive(:popen3)

        expect { command.execute({}, {}) }.not_to output(/Processing Issue/).to_stdout
      end
    end

    context 'when no phase configuration exists' do
      let(:issues) do
        [
          Soba::Domain::Issue.new(
            number: 10,
            title: 'Issue 10',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          ),
        ]
      end

      before do
        allow(github_client).to receive(:issues).and_return(issues)
        Soba::Configuration.configure do |c|
          c.phase.plan.command = nil
        end
      end

      it 'updates labels but skips workflow execution' do
        expect(github_client).to receive(:update_issue_labels).with(10, from: 'soba:todo', to: 'soba:planning')
        expect(Open3).not_to receive(:popen3)

        expect { command.execute({}, {}) }.to output(/Workflow skipped/).to_stdout
      end
    end
  end
end