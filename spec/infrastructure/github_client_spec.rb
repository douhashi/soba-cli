# frozen_string_literal: true

require "spec_helper"
require "soba/infrastructure/github_client"
require "soba/infrastructure/errors"

RSpec.describe Soba::Infrastructure::GitHubClient do
  let(:github_client) { described_class.new(token: "test_token") }
  let(:repository) { "owner/repo" }

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
end