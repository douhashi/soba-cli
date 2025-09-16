# frozen_string_literal: true

require "spec_helper"
require "soba/commands/issue/watch"
require "vcr"

RSpec.describe "Issue Watching Integration", :vcr do
  let(:repository) { "douhashi/soba-test" }
  let(:command) { Soba::Commands::Issue::Watch.new }

  describe "watching issues" do
    let(:watcher) { instance_double(Soba::Services::IssueWatcher) }

    before do
      allow(Soba::Services::IssueWatcher).to receive(:new).and_return(watcher)
      allow(watcher).to receive(:start)
    end

    context "with valid repository" do
      it "starts the watcher with configured settings" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 20
        )

        command.execute(
          repository: repository,
          interval: 20,
          config: nil
        )
      end
    end

    context "with configuration file" do
      let(:config_file) do
        Tempfile.new(["config", ".yml"]).tap do |f|
          f.write(<<~YAML)
            github:
              token: test-token
              repository: douhashi/soba
            workflow:
              interval: 30
          YAML
          f.flush
        end
      end

      after do
        config_file.close
        config_file.unlink
      end

      it "loads configuration and uses the interval" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 30
        )

        command.execute(
          repository: repository,
          interval: nil,
          config: config_file.path
        )
      end
    end
  end

  describe "VCR cassette integration" do
    context "when fetching real issues" do
      it "retrieves and displays issues from GitHub" do
        skip "VCR cassette needs to be recorded with valid token"
      end
    end
  end

  describe "error handling integration" do
    it "handles network errors gracefully" do
      client = instance_double(Soba::Infrastructure::GitHubClient)
      allow(client).to receive(:issues).
        and_raise(Soba::Infrastructure::NetworkError, "Connection failed")

      watcher = Soba::Services::IssueWatcher.new(github_client: client)
      allow(watcher).to receive(:running?).and_return(true, false)
      allow(watcher).to receive(:sleep)

      expect(watcher.logger).to receive(:error).with(
        "Failed to fetch issues",
        hash_including(error: "Connection failed")
      )

      expect { watcher.start(repository: repository, interval: 20) }.
        to output(/Network error/).
        to_stdout
    end

    it "handles rate limit errors with delay" do
      client = instance_double(Soba::Infrastructure::GitHubClient)
      allow(client).to receive(:issues).
        and_raise(Soba::Infrastructure::RateLimitExceeded, "API rate limit exceeded")

      watcher = Soba::Services::IssueWatcher.new(github_client: client)
      # First running? returns true for the initial check, then false to exit the loop
      allow(watcher).to receive(:running?).and_return(true, false, false)
      allow(watcher).to receive(:sleep)

      expect { watcher.start(repository: repository, interval: 20) }.
        to output(/Rate limit exceeded/).
        to_stdout
    end
  end
end