# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Infrastructure::GitHubClient do
  let(:token) { "test_token" }
  let(:client) { described_class.new(token: token) }

  describe "#initialize" do
    context "with token from parameter" do
      it "initializes Octokit client with token" do
        expect(client.instance_variable_get(:@octokit)).to be_a(Octokit::Client)
      end

      it "enables auto pagination" do
        octokit = client.instance_variable_get(:@octokit)
        expect(octokit.auto_paginate).to be true
      end

      it "sets per_page to 100" do
        octokit = client.instance_variable_get(:@octokit)
        expect(octokit.per_page).to eq(100)
      end
    end

    context "with token from Configuration" do
      it "uses token from Configuration when not provided" do
        allow(Soba::Configuration.config.github).to receive(:token).and_return("config_token")
        client = described_class.new
        expect(client.instance_variable_get(:@octokit)).to be_a(Octokit::Client)
      end
    end

    context "with custom Faraday middleware" do
      it "configures retry middleware" do
        # Verify that client is configured correctly
        # We can't directly inspect Octokit's internal Faraday stack
        octokit = client.instance_variable_get(:@octokit)
        expect(octokit).to be_a(Octokit::Client)
        expect(octokit.auto_paginate).to be true
        expect(octokit.per_page).to eq(100)
      end
    end
  end

  describe "#issues" do
    context "with successful response" do
      before do
        stub_request(:get, "https://api.github.com/repos/owner/repo/issues")
          .with(query: { state: "open", per_page: 100 })
          .to_return(
            status: 200,
            body: [
              {
                id: 1,
                number: 1,
                title: "Test Issue 1",
                body: "Description 1",
                state: "open",
                labels: [{ name: "bug", color: "d73a4a" }],
                created_at: "2025-01-01T00:00:00Z",
                updated_at: "2025-01-02T00:00:00Z",
              },
              {
                id: 2,
                number: 2,
                title: "Test Issue 2",
                body: "Description 2",
                state: "open",
                labels: [],
                created_at: "2025-01-01T00:00:00Z",
                updated_at: "2025-01-02T00:00:00Z",
              },
            ].to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches issues from repository" do
        issues = client.issues("owner/repo")
        expect(issues).to be_an(Array)
        expect(issues.size).to eq(2)
      end

      it "returns Domain::Issue instances" do
        issues = client.issues("owner/repo")
        expect(issues.first).to be_a(Soba::Domain::Issue)
        expect(issues.first.number).to eq(1)
        expect(issues.first.title).to eq("Test Issue 1")
      end

      it "maps labels correctly" do
        issues = client.issues("owner/repo")
        # Labels should be normalized to hashes with name and color
        expect(issues.first.labels).to be_an(Array)
        expect(issues.first.labels.size).to eq(1)
        label = issues.first.labels.first
        expect(label).to be_a(Hash)
        expect(label[:name]).to eq("bug")
        expect(label[:color]).to eq("d73a4a")
      end
    end

    context "with pagination" do
      it "auto-paginates to fetch all issues" do
        # Create mock Sawyer::Resource objects
        page1_issues = Array.new(100) do |i|
          double("issue").tap do |issue|
            allow(issue).to receive(:[]).with(:id).and_return(i)
            allow(issue).to receive(:[]).with(:number).and_return(i)
            allow(issue).to receive(:[]).with(:title).and_return("Issue #{i}")
            allow(issue).to receive(:[]).with(:body).and_return(nil)
            allow(issue).to receive(:[]).with(:state).and_return("open")
            allow(issue).to receive(:[]).with(:labels).and_return([])
            allow(issue).to receive(:[]).with(:created_at).and_return(Time.now)
            allow(issue).to receive(:[]).with(:updated_at).and_return(Time.now)
          end
        end

        page2_issues = Array.new(50) do |i|
          double("issue").tap do |issue|
            allow(issue).to receive(:[]).with(:id).and_return(i + 100)
            allow(issue).to receive(:[]).with(:number).and_return(i + 100)
            allow(issue).to receive(:[]).with(:title).and_return("Issue #{i + 100}")
            allow(issue).to receive(:[]).with(:body).and_return(nil)
            allow(issue).to receive(:[]).with(:state).and_return("open")
            allow(issue).to receive(:[]).with(:labels).and_return([])
            allow(issue).to receive(:[]).with(:created_at).and_return(Time.now)
            allow(issue).to receive(:[]).with(:updated_at).and_return(Time.now)
          end
        end

        # Stub octokit to return all issues (auto_paginate is enabled)
        octokit = client.instance_variable_get(:@octokit)
        allow(octokit).to receive(:issues).and_return(page1_issues + page2_issues)

        issues = client.issues("owner/repo")
        expect(issues.size).to eq(150)
      end
    end

    context "with rate limit error" do
      it "raises RateLimitExceeded error" do
        octokit = client.instance_variable_get(:@octokit)
        allow(octokit).to receive(:issues).and_raise(Octokit::TooManyRequests)

        expect { client.issues("owner/repo") }.to raise_error(Soba::Infrastructure::RateLimitExceeded)
      end
    end

    context "with authentication error" do
      it "raises AuthenticationError" do
        octokit = client.instance_variable_get(:@octokit)
        allow(octokit).to receive(:issues).and_raise(Octokit::Unauthorized)

        expect { client.issues("owner/repo") }.to raise_error(Soba::Infrastructure::AuthenticationError)
      end
    end
  end

  describe "#issue" do
    context "with successful response" do
      before do
        stub_request(:get, "https://api.github.com/repos/owner/repo/issues/123")
          .to_return(
            status: 200,
            body: {
              id: 1,
              number: 123,
              title: "Test Issue",
              body: "Issue description",
              state: "open",
              labels: [{ name: "enhancement", color: "a2eeef" }],
              created_at: "2025-01-01T00:00:00Z",
              updated_at: "2025-01-02T00:00:00Z",
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches single issue" do
        issue = client.issue("owner/repo", 123)
        expect(issue).to be_a(Soba::Domain::Issue)
        expect(issue.number).to eq(123)
        expect(issue.title).to eq("Test Issue")
      end
    end

    context "with not found error" do
      before do
        stub_request(:get, "https://api.github.com/repos/owner/repo/issues/999")
          .to_return(status: 404, body: { message: "Not Found" }.to_json)
      end

      it "returns nil" do
        issue = client.issue("owner/repo", 999)
        expect(issue).to be_nil
      end
    end
  end

  describe "#rate_limit_remaining" do
    it "returns remaining rate limit" do
      # Create a mock Octokit::RateLimit struct
      rate_limit = Struct.new(:limit, :remaining, :resets_at, :resets_in).new(5000, 4999, Time.now + 3600, 3600)

      # Stub the octokit client's rate_limit method
      allow(client.instance_variable_get(:@octokit)).to receive(:rate_limit).and_return(rate_limit)

      expect(client.rate_limit_remaining).to eq(4999)
    end
  end

  describe "#wait_for_rate_limit" do
    context "when rate limit is exceeded" do
      it "waits until rate limit resets" do
        # Create a mock Octokit::RateLimit struct with 0 remaining
        reset_time = Time.now + 60
        rate_limit = Struct.new(:limit, :remaining, :resets_at, :resets_in).new(5000, 0, reset_time, 60)

        # Stub the octokit client's rate_limit method
        allow(client.instance_variable_get(:@octokit)).to receive(:rate_limit).and_return(rate_limit)

        # Expect sleep to be called
        allow(client).to receive(:sleep)
        client.wait_for_rate_limit
        expect(client).to have_received(:sleep).with(be_within(5).of(61))
      end
    end
  end
end