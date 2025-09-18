# frozen_string_literal: true

require "spec_helper"
require "soba/services/workflow_integrity_checker"

RSpec.describe Soba::Services::WorkflowIntegrityChecker do
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:logger) { instance_double(Logger) }
  let(:checker) { described_class.new(github_client: github_client, logger: logger) }
  let(:repository) { "owner/repo" }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe "#check_and_fix" do
    context "when no active issues exist" do
      let(:issues) { [] }

      it "returns result with no violations" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be false
        expect(result[:fixed_count]).to eq(0)
        expect(result[:violations]).to be_empty
      end
    end

    context "when single active issue exists" do
      let(:issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Active Issue",
          labels: [{ name: "soba:planning" }]
        )
      end
      let(:issues) { [issue] }

      it "returns result with no violations" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be false
        expect(result[:fixed_count]).to eq(0)
      end
    end

    context "when multiple active issues exist" do
      let(:older_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 1,
          title: "Older Issue",
          labels: [{ name: "soba:planning" }],
          created_at: Time.now - 3600
        )
      end

      let(:newer_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 2,
          title: "Newer Issue",
          labels: [{ name: "soba:doing" }],
          created_at: Time.now - 1800
        )
      end

      let(:issues) { [older_issue, newer_issue] }

      before do
        allow(github_client).to receive(:update_issue_labels)
      end

      it "detects violations and fixes by keeping newest issue active" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be true
        expect(result[:fixed_count]).to eq(1)
        expect(result[:violations]).to include(
          hash_including(
            issue_number: 1,
            label: "soba:planning",
            action: "removed"
          )
        )

        expect(github_client).to have_received(:update_issue_labels).with(
          1,
          from: "soba:planning",
          to: "soba:todo"
        )
      end
    end

    context "when multiple issues with same active label exist" do
      let(:issue1) do
        instance_double(
          Soba::Domain::Issue,
          number: 3,
          title: "Issue 3",
          labels: [{ name: "soba:queued" }],
          created_at: Time.now - 1000
        )
      end

      let(:issue2) do
        instance_double(
          Soba::Domain::Issue,
          number: 5,
          title: "Issue 5",
          labels: [{ name: "soba:queued" }],
          created_at: Time.now - 500
        )
      end

      let(:issues) { [issue1, issue2] }

      before do
        allow(github_client).to receive(:update_issue_labels)
      end

      it "keeps the newest issue and reverts others" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be true
        expect(result[:fixed_count]).to eq(1)

        # Should revert the older issue (issue1)
        expect(github_client).to have_received(:update_issue_labels).with(
          3,
          from: "soba:queued",
          to: "soba:todo"
        )
      end
    end

    context "when intermediate state issues conflict with active issues" do
      let(:active_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 10,
          title: "Active Issue",
          labels: [{ name: "soba:doing" }],
          created_at: Time.now - 1000
        )
      end

      let(:intermediate_issue) do
        instance_double(
          Soba::Domain::Issue,
          number: 11,
          title: "Intermediate Issue",
          labels: [{ name: "soba:review-requested" }],
          created_at: Time.now - 500
        )
      end

      let(:issues) { [active_issue, intermediate_issue] }

      before do
        allow(github_client).to receive(:update_issue_labels)
      end

      it "keeps the newest issue regardless of state type" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be true
        expect(result[:fixed_count]).to eq(1)

        # Should revert the older active issue since intermediate is newer
        expect(github_client).to have_received(:update_issue_labels).with(
          10,
          from: "soba:doing",
          to: "soba:todo"
        )
      end
    end

    context "when fix attempt fails" do
      let(:issue1) do
        instance_double(
          Soba::Domain::Issue,
          number: 20,
          title: "Issue 20",
          labels: [{ name: "soba:planning" }],
          created_at: Time.now - 1000
        )
      end

      let(:issue2) do
        instance_double(
          Soba::Domain::Issue,
          number: 21,
          title: "Issue 21",
          labels: [{ name: "soba:doing" }],
          created_at: Time.now - 500
        )
      end

      let(:issues) { [issue1, issue2] }

      before do
        allow(github_client).to receive(:update_issue_labels).
          and_raise(StandardError, "API Error")
      end

      it "logs error and continues with other fixes" do
        result = checker.check_and_fix(repository, issues: issues)

        expect(result[:violations_found]).to be true
        expect(result[:fixed_count]).to eq(0)
        expect(result[:failed_fixes]).to eq(1)
        expect(logger).to have_received(:error).with(/Failed to fix violation/)
      end
    end

    context "when dry_run mode is enabled" do
      let(:issue1) do
        instance_double(
          Soba::Domain::Issue,
          number: 30,
          title: "Issue 30",
          labels: [{ name: "soba:planning" }],
          created_at: Time.now - 1000
        )
      end

      let(:issue2) do
        instance_double(
          Soba::Domain::Issue,
          number: 31,
          title: "Issue 31",
          labels: [{ name: "soba:doing" }],
          created_at: Time.now - 500
        )
      end

      let(:issues) { [issue1, issue2] }

      before do
        allow(github_client).to receive(:update_issue_labels)  # スパイとして設定
      end

      it "detects violations but does not fix them" do
        result = checker.check_and_fix(repository, issues: issues, dry_run: true)

        expect(result[:violations_found]).to be true
        expect(result[:fixed_count]).to eq(0)
        expect(result[:dry_run]).to be true
        expect(result[:violations]).not_to be_empty

        expect(github_client).not_to have_received(:update_issue_labels)
      end
    end
  end
end