# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Infrastructure::GitHubClient, :vcr do
  let(:client) { described_class.new(token: "test_token") }

  describe "#issues" do
    it "fetches issues from repository" do
      stub_request(:get, "https://api.github.com/repos/owner/repo/issues")
        .with(query: { state: "open" })
        .to_return(
          status: 200,
          body: [
            { id: 1, number: 1, title: "Test Issue 1", state: "open" },
            { id: 2, number: 2, title: "Test Issue 2", state: "open" },
          ].to_json,
          headers: { "Content-Type" => "application/json" },
        )

      issues = client.issues("owner/repo")
      expect(issues).to be_an(Array)
      expect(issues.size).to eq(2)
    end
  end

  describe "#issue" do
    it "fetches single issue" do
      stub_request(:get, "https://api.github.com/repos/owner/repo/issues/123")
        .to_return(
          status: 200,
          body: { id: 1, number: 123, title: "Test Issue", state: "open" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

      issue = client.issue("owner/repo", 123)
      expect(issue[:number]).to eq(123)
    end
  end
end