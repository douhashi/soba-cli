# frozen_string_literal: true

require "spec_helper"
require "soba/services/auto_merge_service"
require "soba/infrastructure/github_client"
require "soba/configuration"

RSpec.describe Soba::Services::AutoMergeService do
  let(:service) { described_class.new }
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:repository) { "owner/repo" }

  before do
    allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
    allow(Soba::Configuration.config.github).to receive(:repository).and_return(repository)
  end

  describe "#execute" do
    context "when there are approved PRs" do
      let(:approved_prs) do
        [
          { number: 10, title: "Feature PR", labels: [{ name: "soba:lgtm" }] },
          { number: 15, title: "Bug fix PR", labels: [{ name: "soba:lgtm" }] },
        ]
      end

      before do
        allow(github_client).to receive(:search_pull_requests).
          with(repository: repository, labels: ["soba:lgtm"]).
          and_return(approved_prs)
      end

      context "when PRs are mergeable" do
        before do
          approved_prs.each do |pr|
            allow(github_client).to receive(:get_pull_request).
              with(repository, pr[:number]).
              and_return(pr.merge(mergeable: true, mergeable_state: "clean", body: "fixes #58"))
          end

          allow(github_client).to receive(:merge_pull_request).
            with(repository, anything, merge_method: "squash").
            and_return({ merged: true, sha: "abc123" })

          allow(github_client).to receive(:get_pr_issue_number).
            with(repository, anything).
            and_return(58)

          allow(github_client).to receive(:close_issue_with_label).
            with(repository, 58, label: "soba:merged").
            and_return(true)
        end

        it "merges all approved PRs" do
          expect(github_client).to receive(:merge_pull_request).
            with(repository, 10, merge_method: "squash")
          expect(github_client).to receive(:merge_pull_request).
            with(repository, 15, merge_method: "squash")

          result = service.execute

          expect(result[:merged_count]).to eq(2)
          expect(result[:failed_count]).to eq(0)
        end

        it "closes related issues with merged label" do
          expect(github_client).to receive(:close_issue_with_label).
            with(repository, 58, label: "soba:merged").
            twice

          service.execute
        end
      end

      context "when a PR is not mergeable" do
        before do
          allow(github_client).to receive(:get_pull_request).
            with(repository, 10).
            and_return({ number: 10, mergeable: false, mergeable_state: "conflicted" })

          allow(github_client).to receive(:get_pull_request).
            with(repository, 15).
            and_return({ number: 15, mergeable: true, mergeable_state: "clean", body: "fixes #59" })

          allow(github_client).to receive(:merge_pull_request).
            with(repository, 15, merge_method: "squash").
            and_return({ merged: true, sha: "def456" })

          allow(github_client).to receive(:get_pr_issue_number).
            with(repository, 15).
            and_return(59)

          allow(github_client).to receive(:close_issue_with_label).
            with(repository, 59, label: "soba:merged").
            and_return(true)
        end

        it "skips non-mergeable PRs and merges others" do
          expect(github_client).not_to receive(:merge_pull_request).
            with(repository, 10, merge_method: "squash")

          expect(github_client).to receive(:merge_pull_request).
            with(repository, 15, merge_method: "squash")

          result = service.execute

          expect(result[:merged_count]).to eq(1)
          expect(result[:failed_count]).to eq(1)
          expect(result[:details][:failed].first).to include(number: 10, reason: /conflict/)
        end
      end

      context "when merge operation fails" do
        before do
          allow(github_client).to receive(:get_pull_request).
            with(repository, 10).
            and_return({ number: 10, mergeable: true, mergeable_state: "clean" })

          allow(github_client).to receive(:get_pull_request).
            with(repository, 15).
            and_return({ number: 15, mergeable: true, mergeable_state: "clean" })

          allow(github_client).to receive(:merge_pull_request).
            with(repository, 10, merge_method: "squash").
            and_raise(Soba::Infrastructure::MergeConflictError.new("Cannot merge"))

          allow(github_client).to receive(:merge_pull_request).
            with(repository, 15, merge_method: "squash").
            and_raise(Soba::Infrastructure::MergeConflictError.new("Cannot merge"))
        end

        it "handles merge errors gracefully" do
          result = service.execute

          expect(result[:merged_count]).to eq(0)
          expect(result[:failed_count]).to eq(2)
          expect(result[:details][:failed].first).to include(number: 10, reason: /Cannot merge/)
        end
      end
    end

    context "when there are no approved PRs" do
      before do
        allow(github_client).to receive(:search_pull_requests).
          with(repository: repository, labels: ["soba:lgtm"]).
          and_return([])
      end

      it "returns zero counts" do
        result = service.execute

        expect(result[:merged_count]).to eq(0)
        expect(result[:failed_count]).to eq(0)
        expect(result[:details][:merged]).to be_empty
        expect(result[:details][:failed]).to be_empty
      end
    end
  end

  describe "#find_approved_prs" do
    it "searches for PRs with soba:lgtm label" do
      expect(github_client).to receive(:search_pull_requests).
        with(repository: repository, labels: ["soba:lgtm"]).
        and_return([])

      service.send(:find_approved_prs)
    end
  end

  describe "#check_mergeable" do
    let(:pr_number) { 10 }

    context "when PR is mergeable" do
      before do
        allow(github_client).to receive(:get_pull_request).
          with(repository, pr_number).
          and_return({ mergeable: true, mergeable_state: "clean" })
      end

      it "returns true" do
        expect(service.send(:check_mergeable, pr_number)).to be true
      end
    end

    context "when PR has conflicts" do
      before do
        allow(github_client).to receive(:get_pull_request).
          with(repository, pr_number).
          and_return({ mergeable: false, mergeable_state: "conflicted" })
      end

      it "returns false" do
        expect(service.send(:check_mergeable, pr_number)).to be false
      end
    end

    context "when mergeable_state is not clean" do
      before do
        allow(github_client).to receive(:get_pull_request).
          with(repository, pr_number).
          and_return({ mergeable: true, mergeable_state: "unstable" })
      end

      it "returns false" do
        expect(service.send(:check_mergeable, pr_number)).to be false
      end
    end
  end
end