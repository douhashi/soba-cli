# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Services::QueueingService do
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:blocking_checker) { instance_double(Soba::Services::WorkflowBlockingChecker) }
  let(:logger) { instance_double(Logger) }
  let(:service) { described_class.new(github_client: github_client, blocking_checker: blocking_checker, logger: logger) }
  let(:repository) { "owner/repo" }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
  end

  describe "#queue_next_issue" do
    context "when active issue exists" do
      let(:issues) { [todo_issue] }
      let(:todo_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).with(repository, state: "open").and_return(issues)
        allow(blocking_checker).to receive(:blocking?).with(repository, issues: issues).and_return(true)
      end

      it "skips queueing and logs the reason" do
        allow(blocking_checker).to receive(:blocking_reason).with(repository, issues: issues).and_return("Issue #2 が soba:planning のため、新しいワークフローの開始をスキップしました")

        result = service.queue_next_issue(repository)

        expect(result).to be_nil
        expect(logger).to have_received(:info).with("キューイング処理をスキップします: Issue #2 が soba:planning のため、新しいワークフローの開始をスキップしました")
      end
    end

    context "when no active issue exists" do
      let(:issues) { [todo_issue] }
      let(:todo_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).with(repository, state: "open").and_return(issues)
        allow(blocking_checker).to receive(:blocking?).with(repository, issues: issues).and_return(false)
      end

      context "and no todo issues exist" do
        let(:issues) { [] }

        it "returns nil and logs no candidates message" do
          result = service.queue_next_issue(repository)

          expect(result).to be_nil
          expect(logger).to have_received(:info).with("キューイング対象のIssueが見つかりませんでした")
        end
      end

      context "and todo issue exists" do
        before do
          allow(github_client).to receive(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
        end

        it "queues the todo issue" do
          result = service.queue_next_issue(repository)

          expect(result).to eq(todo_issue)
          expect(github_client).to have_received(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
          expect(logger).to have_received(:info).with("Issue #1 を soba:queued に遷移させました: Todo Issue")
        end
      end

      context "and multiple todo issues exist" do
        let(:todo_issue_1) do
          instance_double(
            Soba::Domain::Issue,
            number: 3,
            title: "Todo Issue 3",
            labels: [{ name: "soba:todo" }]
          )
        end

        let(:todo_issue_2) do
          instance_double(
            Soba::Domain::Issue,
            number: 1,
            title: "Todo Issue 1",
            labels: [{ name: "soba:todo" }]
          )
        end

        let(:todo_issue_3) do
          instance_double(
            Soba::Domain::Issue,
            number: 5,
            title: "Todo Issue 5",
            labels: [{ name: "soba:todo" }]
          )
        end

        let(:issues) { [todo_issue_1, todo_issue_2, todo_issue_3] }

        before do
          allow(github_client).to receive(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
        end

        it "queues the todo issue with smallest number" do
          result = service.queue_next_issue(repository)

          expect(result).to eq(todo_issue_2)
          expect(github_client).to have_received(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
          expect(logger).to have_received(:info).with("Issue #1 を soba:queued に遷移させました: Todo Issue 1")
        end
      end

      context "when label update fails" do
        before do
          allow(github_client).to receive(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued").and_raise(StandardError, "GitHub API error")
          allow(logger).to receive(:error)
        end

        it "logs error and re-raises exception" do
          expect { service.queue_next_issue(repository) }.to raise_error(StandardError, "GitHub API error")
          expect(logger).to have_received(:error).with("Issue #1 のラベル更新に失敗しました: GitHub API error")
        end
      end
    end

    context "when mixed issues exist" do
      let(:todo_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 2,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      let(:ready_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Ready Issue",
          labels: [{ name: "soba:ready" }]
        )
      end

      let(:bug_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 3,
          title: "Bug Issue",
          labels: [{ name: "bug" }]
        )
      end

      let(:issues) { [ready_issue, todo_issue, bug_issue] }

      before do
        allow(github_client).to receive(:issues).with(repository, state: "open").and_return(issues)
        allow(blocking_checker).to receive(:blocking?).with(repository, issues: issues).and_return(false)
        allow(github_client).to receive(:update_issue_labels).with(2, from: "soba:todo", to: "soba:queued")
      end

      it "queues only the todo issue" do
        result = service.queue_next_issue(repository)

        expect(result).to eq(todo_issue)
        expect(github_client).to have_received(:update_issue_labels).with(2, from: "soba:todo", to: "soba:queued")
      end
    end
  end

  describe "#has_active_issue?" do
    let(:issues) { [todo_issue] }
    let(:todo_issue) do
      instance_double(
        Soba::Domain::Issue,
        number: 1,
        title: "Todo Issue",
        labels: [{ name: "soba:todo" }]
      )
    end

    before do
      allow(github_client).to receive(:issues).with(repository, state: "open").and_return(issues)
    end

    context "when blocking checker returns true" do
      before do
        allow(blocking_checker).to receive(:blocking?).with(repository, issues: issues).and_return(true)
      end

      it "returns true" do
        result = service.send(:has_active_issue?, repository)
        expect(result).to be true
      end
    end

    context "when blocking checker returns false" do
      before do
        allow(blocking_checker).to receive(:blocking?).with(repository, issues: issues).and_return(false)
      end

      it "returns false" do
        result = service.send(:has_active_issue?, repository)
        expect(result).to be false
      end
    end
  end

  describe "#find_next_candidate" do
    context "when no todo issues exist" do
      let(:issues) { [] }

      it "returns nil" do
        result = service.send(:find_next_candidate, issues)
        expect(result).to be_nil
      end
    end

    context "when single todo issue exists" do
      let(:todo_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end
      let(:issues) { [todo_issue] }

      it "returns the todo issue" do
        result = service.send(:find_next_candidate, issues)
        expect(result).to eq(todo_issue)
      end
    end

    context "when multiple todo issues exist" do
      let(:todo_issue_1) do
        instance_double(
          Soba::Domain::Issue,
          number: 3,
          title: "Todo Issue 3",
          labels: [{ name: "soba:todo" }]
        )
      end

      let(:todo_issue_2) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Todo Issue 1",
          labels: [{ name: "soba:todo" }]
        )
      end

      let(:issues) { [todo_issue_1, todo_issue_2] }

      it "returns the issue with smallest number" do
        result = service.send(:find_next_candidate, issues)
        expect(result).to eq(todo_issue_2)
      end
    end

    context "when mixed issues exist" do
      let(:todo_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 2,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      let(:ready_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Ready Issue",
          labels: [{ name: "soba:ready" }]
        )
      end

      let(:issues) { [ready_issue, todo_issue] }

      it "returns only the todo issue" do
        result = service.send(:find_next_candidate, issues)
        expect(result).to eq(todo_issue)
      end
    end
  end

  describe "#transition_to_queued" do
    let(:issue) do
      instance_double(
        Soba::Domain::Issue,
        number: 1,
        title: "Todo Issue",
        labels: [{ name: "soba:todo" }]
      )
    end

    context "when label update succeeds" do
      before do
        allow(github_client).to receive(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
      end

      it "updates the issue labels and logs success" do
        service.send(:transition_to_queued, issue)

        expect(github_client).to have_received(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued")
        expect(logger).to have_received(:info).with("Issue #1 を soba:queued に遷移させました: Todo Issue")
      end
    end

    context "when label update fails" do
      before do
        allow(github_client).to receive(:update_issue_labels).with(1, from: "soba:todo", to: "soba:queued").and_raise(StandardError, "GitHub API error")
        allow(logger).to receive(:error)
      end

      it "logs error and re-raises exception" do
        expect { service.send(:transition_to_queued, issue) }.to raise_error(StandardError, "GitHub API error")
        expect(logger).to have_received(:error).with("Issue #1 のラベル更新に失敗しました: GitHub API error")
      end
    end
  end
end