# frozen_string_literal: true

require "spec_helper"
require "soba/infrastructure/github_client"
require "soba/infrastructure/errors"

RSpec.describe Soba::Infrastructure::GitHubClient do
  let(:github_client) { described_class.new(token: "test_token") }
  let(:repository) { "owner/repo" }

  describe "#initialize" do
    context "when token is explicitly provided" do
      it "uses the provided token" do
        client = described_class.new(token: "explicit_token")
        expect(client.octokit.access_token).to eq("explicit_token")
      end
    end

    context "when token is not provided" do
      context "when Configuration is available with auth_method" do
        before do
          allow(Soba::Configuration).to receive(:config).and_return(
            double(github: double(token: nil, auth_method: 'gh'))
          )
        end

        it "uses GitHubTokenProvider with specified auth_method" do
          token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
          allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
          allow(token_provider).to receive(:fetch).with(auth_method: 'gh').and_return('gh_token')

          client = described_class.new
          expect(client.octokit.access_token).to eq('gh_token')
        end
      end

      context "when Configuration has token set" do
        before do
          allow(Soba::Configuration).to receive(:config).and_return(
            double(github: double(token: 'config_token', auth_method: nil))
          )
        end

        it "uses the configuration token" do
          client = described_class.new
          expect(client.octokit.access_token).to eq('config_token')
        end
      end

      context "when using environment variable fallback" do
        before do
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('env_token')
          allow(ENV).to receive(:[]).with('DEBUG').and_return(nil)
          stub_const("Soba::Configuration", nil)
        end

        it "uses the environment variable" do
          client = described_class.new
          expect(client.octokit.access_token).to eq('env_token')
        end
      end
    end
  end

  describe "#list_labels" do
    context "when labels exist" do
      it "returns the list of labels" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(
            status: 200,
            body: [
              { name: "bug", color: "d73a4a", description: "Something isn't working" },
              { name: "soba:planning", color: "1e90ff", description: "Planning phase" },
            ].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.list_labels(repository)

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first[:name]).to eq("bug")
        expect(result.first[:color]).to eq("d73a4a")
        expect(result.last[:name]).to eq("soba:planning")
      end
    end

    context "when no labels exist" do
      it "returns an empty array" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(
            status: 200,
            body: [].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.list_labels(repository)

        expect(result).to be_empty
      end
    end

    context "when an error occurs" do
      it "raises an error with appropriate message" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(status: 404, body: "Not Found")

        expect { github_client.list_labels(repository) }.
          to raise_error(Octokit::NotFound)
      end
    end
  end

  describe "#update_issue_labels" do
    let(:issue_number) { 42 }
    let(:from_label) { "soba:todo" }
    let(:to_label) { "soba:queued" }

    context "when repository argument is provided (atomic version)" do
      context "when expected label state matches" do
        it "updates labels successfully" do
          # First fetch current labels
          stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/issues\/42$/).
            to_return(
              status: 200,
              body: {
                number: 42,
                labels: [{ name: "soba:todo", color: "green" }],
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          # Update labels
          stub_request(:put, /api\.github\.com\/repos\/owner\/repo\/issues\/42\/labels/).
            to_return(
              status: 200,
              body: [{ name: "soba:queued", color: "blue" }].to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = github_client.update_issue_labels(repository, issue_number, from: from_label, to: to_label)

          expect(result).to eq(true)
        end
      end

      context "when expected label state does not match" do
        it "returns false without updating" do
          # Current labels don't have expected 'from' label
          stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/issues\/42$/).
            to_return(
              status: 200,
              body: {
                number: 42,
                labels: [{ name: "soba:planning", color: "yellow" }],
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = github_client.update_issue_labels(repository, issue_number, from: from_label, to: to_label)

          expect(result).to eq(false)
        end
      end

      context "when to label already exists" do
        it "returns false to prevent duplicate transition" do
          # Issue already has the 'to' label
          stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/issues\/42$/).
            to_return(
              status: 200,
              body: {
                number: 42,
                labels: [{ name: "soba:queued", color: "blue" }],
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = github_client.update_issue_labels(repository, issue_number, from: from_label, to: to_label)

          expect(result).to eq(false)
        end
      end
    end
  end

  describe "#create_label" do
    let(:label_name) { "soba:planning" }
    let(:color) { "1e90ff" }
    let(:description) { "Planning phase" }

    context "when label creation succeeds" do
      it "creates a new label and returns it" do
        stub_request(:post, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(
            status: 201,
            body: { name: label_name, color: color, description: description }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.create_label(repository, label_name, color, description)

        expect(result[:name]).to eq(label_name)
        expect(result[:color]).to eq(color)
        expect(result[:description]).to eq(description)
      end
    end

    context "when label already exists" do
      it "returns nil and logs the skip" do
        stub_request(:post, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(
            status: 422,
            body: { message: "Validation failed", errors: [{ code: "already_exists" }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.create_label(repository, label_name, color, description)

        expect(result).to be_nil
      end
    end

    context "when authentication fails" do
      it "raises AuthenticationError" do
        stub_request(:post, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(status: 401, body: "Bad credentials")

        expect { github_client.create_label(repository, label_name, color, description) }.
          to raise_error(Soba::Infrastructure::AuthenticationError, /Authentication failed/)
      end
    end

    context "when forbidden due to insufficient permissions" do
      it "raises GitHubClientError with permission message" do
        stub_request(:post, /api\.github\.com\/repos\/owner\/repo\/labels/).
          to_return(status: 403, body: "Forbidden")

        expect { github_client.create_label(repository, label_name, color, description) }.
          to raise_error(Soba::Infrastructure::GitHubClientError, /Access forbidden/)
      end
    end
  end

  describe "#search_pull_requests" do
    context "when searching with labels" do
      it "returns pull requests with specified labels" do
        stub_request(:get, "https://api.github.com/search/issues").
          with(query: hash_including("q" => "type:pr is:open repo:owner/repo label:soba:lgtm")).
          to_return(
            status: 200,
            body: {
              total_count: 2,
              items: [
                { number: 10, title: "Feature PR", state: "open", labels: [{ name: "soba:lgtm" }] },
                { number: 15, title: "Bug fix PR", state: "open", labels: [{ name: "soba:lgtm" }] },
              ],
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.search_pull_requests(repository: repository, labels: ["soba:lgtm"])

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first[:number]).to eq(10)
        expect(result.first[:title]).to eq("Feature PR")
      end
    end

    context "when no pull requests match" do
      it "returns an empty array" do
        stub_request(:get, "https://api.github.com/search/issues").
          with(query: hash_including("q" => "type:pr is:open repo:owner/repo label:soba:lgtm")).
          to_return(
            status: 200,
            body: { total_count: 0, items: [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.search_pull_requests(repository: repository, labels: ["soba:lgtm"])

        expect(result).to be_empty
      end
    end
  end

  describe "#merge_pull_request" do
    let(:pr_number) { 10 }

    context "when merge succeeds" do
      it "merges the pull request with squash" do
        stub_request(:put, /api\.github\.com\/repos\/owner\/repo\/pulls\/10\/merge/).
          with(body: hash_including("merge_method" => "squash")).
          to_return(
            status: 200,
            body: { sha: "abc123", merged: true, message: "Pull Request successfully merged" }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.merge_pull_request(repository, pr_number, merge_method: "squash")

        expect(result[:merged]).to be true
        expect(result[:sha]).to eq("abc123")
      end
    end

    context "when merge fails due to conflict" do
      it "returns merged: false with conflict message" do
        stub_request(:put, /api\.github\.com\/repos\/owner\/repo\/pulls\/10\/merge/).
          to_return(
            status: 405,
            body: { message: "Pull Request is not mergeable" }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect { github_client.merge_pull_request(repository, pr_number, merge_method: "squash") }.
          to raise_error(Soba::Infrastructure::MergeConflictError, /not mergeable/)
      end
    end
  end

  describe "#get_pull_request" do
    let(:pr_number) { 10 }

    context "when PR exists" do
      it "returns the PR details" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/pulls\/10/).
          to_return(
            status: 200,
            body: {
              number: 10,
              title: "Feature PR",
              body: "fixes #58",
              state: "open",
              mergeable: true,
              mergeable_state: "clean",
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.get_pull_request(repository, pr_number)

        expect(result[:number]).to eq(10)
        expect(result[:title]).to eq("Feature PR")
        expect(result[:body]).to eq("fixes #58")
        expect(result[:mergeable]).to be true
      end
    end

    context "when PR does not exist" do
      it "raises an error" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/pulls\/10/).
          to_return(status: 404, body: "Not Found")

        expect { github_client.get_pull_request(repository, pr_number) }.
          to raise_error(Octokit::NotFound)
      end
    end
  end

  describe "#get_pr_issue_number" do
    let(:pr_number) { 10 }

    context "when PR body contains fixes keyword" do
      it "extracts the issue number" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/pulls\/10/).
          to_return(
            status: 200,
            body: { body: "This PR fixes #58" }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.get_pr_issue_number(repository, pr_number)

        expect(result).to eq(58)
      end
    end

    context "when PR body does not contain issue reference" do
      it "returns nil" do
        stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/pulls\/10/).
          to_return(
            status: 200,
            body: { body: "This is a simple PR" }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.get_pr_issue_number(repository, pr_number)

        expect(result).to be_nil
      end
    end
  end

  describe "#close_issue_with_label" do
    let(:issue_number) { 58 }

    context "when closing succeeds" do
      it "closes the issue and adds label" do
        # First request to close the issue
        stub_request(:patch, /api\.github\.com\/repos\/owner\/repo\/issues\/58/).
          with(body: hash_including("state" => "closed")).
          to_return(
            status: 200,
            body: { number: 58, state: "closed" }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Second request to add label
        stub_request(:post, /api\.github\.com\/repos\/owner\/repo\/issues\/58\/labels/).
          with(body: ["soba:merged"].to_json).
          to_return(
            status: 200,
            body: [{ name: "soba:merged" }].to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = github_client.close_issue_with_label(repository, issue_number, label: "soba:merged")

        expect(result).to be true
      end
    end
  end
end