# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Services::WorkflowBlockingChecker do
  let(:github_client) { instance_double(Octokit::Client) }
  let(:checker) { described_class.new(github_client: github_client) }
  let(:repository) { "owner/repo" }

  describe "#blocking?" do
    context "when there are no open issues" do
      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([])
      end

      it "returns false" do
        result = checker.blocking?(repository)
        expect(result).to be false
      end
    end

    context "when only soba:todo issues exist" do
      let(:todo_issue) do
        double(
          number: 1,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([todo_issue])
      end

      it "returns false" do
        result = checker.blocking?(repository)
        expect(result).to be false
      end
    end

    context "when soba:planning issue exists" do
      let(:planning_issue) do
        double(
          number: 2,
          title: "Planning Issue",
          labels: [{ name: "soba:planning" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([planning_issue])
      end

      it "returns true" do
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end

    context "when soba:ready issue exists" do
      let(:ready_issue) do
        double(
          number: 3,
          title: "Ready Issue",
          labels: [{ name: "soba:ready" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([ready_issue])
      end

      it "returns true" do
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end

    context "when soba:doing issue exists" do
      let(:doing_issue) do
        double(
          number: 4,
          title: "Doing Issue",
          labels: [{ name: "soba:doing" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([doing_issue])
      end

      it "returns true" do
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end

    context "when soba:review-requested issue exists" do
      let(:review_issue) do
        double(
          number: 5,
          title: "Review Issue",
          labels: [{ name: "soba:review-requested" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([review_issue])
      end

      it "returns true" do
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end

    context "when multiple blocking issues exist" do
      let(:planning_issue) do
        double(
          number: 2,
          title: "Planning Issue",
          labels: [{ name: "soba:planning" }]
        )
      end

      let(:review_issue) do
        double(
          number: 5,
          title: "Review Issue",
          labels: [{ name: "soba:review-requested" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([planning_issue, review_issue])
      end

      it "returns true" do
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end

    context "when non-soba labels exist" do
      let(:other_issue) do
        double(
          number: 6,
          title: "Other Issue",
          labels: [{ name: "bug" }, { name: "enhancement" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([other_issue])
      end

      it "returns false" do
        result = checker.blocking?(repository)
        expect(result).to be false
      end
    end

    context "when new soba: label exists (not in hardcoded list)" do
      let(:custom_soba_issue) do
        double(
          number: 7,
          title: "Custom Soba Issue",
          labels: [{ name: "soba:custom-status" }]
        )
      end

      let(:todo_issue) do
        double(
          number: 8,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      before do
        # 動的検出実装では全てのOpenなIssueを取得
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([custom_soba_issue, todo_issue])
      end

      it "blocks with new soba: labels (except soba:todo)" do
        # 動的検出実装により、新しいsoba:*ラベルも検出される
        result = checker.blocking?(repository)
        expect(result).to be true
      end
    end
  end

  describe "#blocking_issues" do
    context "when there are blocking issues" do
      let(:planning_issue) do
        double(
          number: 2,
          title: "Planning Issue",
          labels: [{ name: "soba:planning" }]
        )
      end

      let(:review_issue) do
        double(
          number: 5,
          title: "Review Issue",
          labels: [{ name: "soba:review-requested" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([planning_issue, review_issue])
      end

      it "returns all blocking issues" do
        issues = checker.blocking_issues(repository)
        expect(issues).to contain_exactly(planning_issue, review_issue)
      end
    end

    context "when there are no blocking issues" do
      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([])
      end

      it "returns empty array" do
        issues = checker.blocking_issues(repository)
        expect(issues).to be_empty
      end
    end

    context "when API call fails" do
      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_raise(Octokit::Error.new)
      end

      it "handles the error gracefully and returns empty array" do
        issues = checker.blocking_issues(repository)
        expect(issues).to be_empty
      end
    end

    context "when there are mixed issues (soba:todo and others)" do
      let(:doing_issue) do
        double(
          number: 4,
          title: "Doing Issue",
          labels: [{ name: "soba:doing" }]
        )
      end

      let(:todo_issue) do
        double(
          number: 9,
          title: "Todo Issue",
          labels: [{ name: "soba:todo" }]
        )
      end

      let(:bug_issue) do
        double(
          number: 10,
          title: "Bug Issue",
          labels: [{ name: "bug" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([doing_issue, todo_issue, bug_issue])
      end

      it "returns only soba: labeled issues (except soba:todo)" do
        issues = checker.blocking_issues(repository)
        expect(issues).to contain_exactly(doing_issue)
      end
    end
  end

  describe "#blocking_reason" do
    context "when a single blocking issue exists" do
      let(:review_issue) do
        double(
          number: 5,
          title: "Review Issue",
          labels: [{ name: "soba:review-requested" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([review_issue])
      end

      it "returns formatted blocking reason" do
        reason = checker.blocking_reason(repository)
        expect(reason).to eq("Issue #5 が soba:review-requested のため、新しいワークフローの開始をスキップしました")
      end
    end

    context "when multiple blocking issues exist" do
      let(:planning_issue) do
        double(
          number: 2,
          title: "Planning Issue",
          labels: [{ name: "soba:planning" }]
        )
      end

      let(:doing_issue) do
        double(
          number: 4,
          title: "Doing Issue",
          labels: [{ name: "soba:doing" }]
        )
      end

      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([planning_issue, doing_issue])
      end

      it "returns reason for the first blocking issue" do
        reason = checker.blocking_reason(repository)
        expect(reason).to match(/Issue #\d+ が soba:\w+/)
      end
    end

    context "when no blocking issues exist" do
      before do
        allow(github_client).to receive(:issues).
          with(repository, state: "open").
          and_return([])
      end

      it "returns nil" do
        reason = checker.blocking_reason(repository)
        expect(reason).to be_nil
      end
    end
  end
end