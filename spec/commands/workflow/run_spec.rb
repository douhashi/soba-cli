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
      c.git.setup_workspace = false # Disable workspace setup for tests
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

      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      before do
        allow(github_client).to receive(:issues).and_return(issues_with_todo)
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        # For todo issue, blocking check is called with except_issue_number
        allow(blocking_checker).to receive(:blocking?).and_return(false)
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

      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      before do
        allow(github_client).to receive(:issues).and_return(issues_with_ready)
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        # For ready issue, blocking check should NOT be called (phase != :todo)
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

      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      before do
        allow(github_client).to receive(:issues).and_return(issues_in_progress)
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        allow(blocking_checker).to receive(:blocking?).with('owner/repo', issues: issues_in_progress).and_return(true)
        allow(blocking_checker).to receive(:blocking_reason).with('owner/repo', issues: issues_in_progress).
          and_return('Issue #4 が soba:planning のため、新しいワークフローの開始をスキップしました')
      end

      it 'skips processing' do
        expect(github_client).not_to receive(:update_issue_labels)
        expect(Open3).not_to receive(:popen3)

        # Stop after first iteration
        allow_any_instance_of(described_class).to receive(:sleep) do |instance, _interval|
          instance.instance_variable_set(:@running, false)
          nil
        end

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

      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      before do
        allow(github_client).to receive(:issues).and_return(issues)
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        allow(blocking_checker).to receive(:blocking?).with('owner/repo', issues: issues).and_return(false)
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

    context 'when workflow is blocked by other soba labels' do
      # ブロッキングロジックはWorkflowBlockingCheckerで単体テスト済みなので
      # ここでは基本的な統合のみテスト
      # ブロッキング機能はWorkflowBlockingCheckerの単体テストで担保されているので
      # 統合テストでは基本的な動作のみ確認
      it 'integrates with WorkflowBlockingChecker' do
        # WorkflowBlockingCheckerが生成されることを確認
        expect(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_call_original

        todo_issue = Soba::Domain::Issue.new(
          number: 20,
          title: 'Todo Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        allow(github_client).to receive(:issues).and_return([todo_issue], [])
        allow(github_client).to receive(:update_issue_labels)
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

    context 'when issue is already in progress' do
      # 進行中のIssueはブロッキングチェックをスキップすることを確認
      it 'does not check blocking for non-todo issues' do
        doing_issue = Soba::Domain::Issue.new(
          number: 50,
          title: 'Doing Issue',
          labels: [{ name: 'soba:doing' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )

        blocking_checker = instance_double(Soba::Services::WorkflowBlockingChecker)
        # Return issues once, then empty
        issues_returned = false
        allow(github_client).to receive(:issues) do
          if !issues_returned
            issues_returned = true
            [doing_issue]
          else
            []
          end
        end
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)

        # Verify that blocking check is NOT called for non-todo issues
        expect(blocking_checker).not_to receive(:blocking?)

        allow(github_client).to receive(:update_issue_labels)
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

    context 'when workflow is not blocked' do
      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      let(:todo_issue) do
        Soba::Domain::Issue.new(
          number: 40,
          title: 'Todo Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )
      end

      before do
        allow(github_client).to receive(:issues).and_return([todo_issue])
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        # blocking? will be called with except_issue_number: 40 for todo issue
        allow(blocking_checker).to receive(:blocking?).and_return(false)
      end

      it 'processes todo issues normally' do
        expect(github_client).to receive(:update_issue_labels).with(40, from: 'soba:todo', to: 'soba:planning')

        allow(Open3).to receive(:popen3).with('echo', 'Plan 40') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Plan executed')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        expect { command.execute({}, {}) }.to output(/Processing Issue #40/).to_stdout
      end
    end

    context 'when tmux execution with enhanced display' do
      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }
      let(:tmux_session_manager) { instance_double(Soba::Services::TmuxSessionManager) }
      let(:workflow_executor) { instance_double(Soba::Services::WorkflowExecutor) }
      let(:issue_processor) { instance_double(Soba::Services::IssueProcessor) }

      let(:todo_issue) do
        Soba::Domain::Issue.new(
          number: 50,
          title: 'Test Issue',
          labels: [{ name: 'soba:todo' }],
          state: 'open',
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601
        )
      end

      before do
        allow(github_client).to receive(:issues).and_return([todo_issue])
        allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
        allow(blocking_checker).to receive(:blocking?).with('owner/repo', issues: [todo_issue]).and_return(false)
        allow(Soba::Services::TmuxSessionManager).to receive(:new).and_return(tmux_session_manager)
        allow(Soba::Services::WorkflowExecutor).to receive(:new).and_return(workflow_executor)
        allow(Soba::Services::IssueProcessor).to receive(:new).and_return(issue_processor)
      end

      context 'when tmux_info is returned' do
        it 'displays enhanced tmux session information with emoji' do
          process_result = {
            success: true,
            phase: 'plan',
            label_updated: true,
            mode: 'tmux',
            tmux_info: {
              session: 'soba-issue-50',
              window: '0',
              pane: '1',
            },
            session_name: 'soba-issue-50',
          }

          allow(issue_processor).to receive(:process).and_return(process_result)

          expect { command.execute({}, {}) }.to output(
            /📺 Session: soba-issue-50.*💡 Monitor: soba monitor soba-issue-50.*📁 Log: ~\/\.soba\/logs\/soba-issue-50\.log/m
          ).to_stdout
        end
      end

      context 'when tmux_info is not present (backward compatibility)' do
        it 'displays legacy tmux session information' do
          process_result = {
            success: true,
            phase: 'plan',
            label_updated: true,
            mode: 'tmux',
            session_name: 'soba-issue-50',
          }

          allow(issue_processor).to receive(:process).and_return(process_result)

          expect { command.execute({}, {}) }.to output(
            /Tmux session started: soba-issue-50.*You can attach with: tmux attach -t soba-issue-50/m
          ).to_stdout
        end
      end

      context 'when error occurs during execution' do
        it 'displays error message with emoji' do
          process_result = {
            success: false,
            error: 'Failed to create tmux session',
          }

          allow(issue_processor).to receive(:process).and_return(process_result)

          expect { command.execute({}, {}) }.to output(
            /❌ Failed: Failed to create tmux session/
          ).to_stdout
        end
      end

      context 'when starting issue processing' do
        it 'displays issue processing message with emoji' do
          process_result = {
            success: true,
            phase: 'plan',
            label_updated: true,
          }

          allow(issue_processor).to receive(:process).and_return(process_result)

          expect { command.execute({}, {}) }.to output(
            /🚀 Processing Issue #50: Test Issue/
          ).to_stdout
        end
      end
    end

    context 'when queueing service integration' do
      let(:queueing_service) { instance_double(Soba::Services::QueueingService) }
      let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }

      context 'when multiple soba:todo issues exist' do
        let(:todo_issues) do
          [
            Soba::Domain::Issue.new(
              number: 100,
              title: 'Todo Issue 100',
              labels: [{ name: 'soba:todo' }],
              state: 'open',
              created_at: Time.now.iso8601,
              updated_at: Time.now.iso8601
            ),
            Soba::Domain::Issue.new(
              number: 101,
              title: 'Todo Issue 101',
              labels: [{ name: 'soba:todo' }],
              state: 'open',
              created_at: Time.now.iso8601,
              updated_at: Time.now.iso8601
            ),
          ]
        end

        before do
          allow(github_client).to receive(:issues).and_return(todo_issues)
          allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
          allow(Soba::Services::QueueingService).to receive(:new).and_return(queueing_service)
          allow(blocking_checker).to receive(:blocking?).and_return(false)
        end

        it 'queues the first todo issue when no active issues' do
          expect(queueing_service).to receive(:queue_next_issue).with('owner/repo').and_return(todo_issues.first)

          # Stop after first iteration
          allow_any_instance_of(described_class).to receive(:sleep) do |instance, _interval|
            instance.instance_variable_set(:@running, false)
            nil
          end

          expect { command.execute({}, {}) }.to output(/Queued Issue #100 for processing/).to_stdout
        end
      end

      context 'when active issue exists' do
        let(:active_issue) do
          Soba::Domain::Issue.new(
            number: 90,
            title: 'Active Issue',
            labels: [{ name: 'soba:planning' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          )
        end

        let(:todo_issue) do
          Soba::Domain::Issue.new(
            number: 91,
            title: 'Todo Issue',
            labels: [{ name: 'soba:todo' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          )
        end

        before do
          allow(github_client).to receive(:issues).and_return([active_issue, todo_issue])
          allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
          allow(Soba::Services::QueueingService).to receive(:new).and_return(queueing_service)
          allow(blocking_checker).to receive(:blocking?).with('owner/repo', issues: [active_issue, todo_issue]).and_return(true)
          allow(blocking_checker).to receive(:blocking_reason).and_return('Issue #90 が soba:planning のため、新しいワークフローの開始をスキップしました')
        end

        it 'skips queueing when active issue is present' do
          expect(queueing_service).not_to receive(:queue_next_issue)

          # Stop after first iteration
          allow_any_instance_of(described_class).to receive(:sleep) do |instance, _interval|
            instance.instance_variable_set(:@running, false)
            nil
          end

          expect { command.execute({}, {}) }.not_to output(/Queued Issue/).to_stdout
        end
      end

      context 'when soba:queued issue exists' do
        let(:queued_issue) do
          Soba::Domain::Issue.new(
            number: 110,
            title: 'Queued Issue',
            labels: [{ name: 'soba:queued' }],
            state: 'open',
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          )
        end

        before do
          allow(github_client).to receive(:issues).and_return([queued_issue])
          allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(blocking_checker)
          allow(Soba::Services::QueueingService).to receive(:new).and_return(queueing_service)
        end

        it 'transitions queued issue to planning' do
          expect(github_client).to receive(:update_issue_labels).with(110, from: 'soba:queued', to: 'soba:planning')

          allow(Open3).to receive(:popen3).with('echo', 'Plan 110') do |&block|
            stdin = double('stdin', close: nil)
            stdout = double('stdout', read: 'Plan executed')
            stderr = double('stderr', read: '')
            thread = double('thread', value: double(exitstatus: 0))
            block.call(stdin, stdout, stderr, thread)
          end

          expect { command.execute({}, {}) }.to output(/Processing Issue #110/).to_stdout
        end
      end
    end
  end
end