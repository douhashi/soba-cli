# frozen_string_literal: true

require "spec_helper"
require "soba/commands/issue/watch"

RSpec.describe Soba::Commands::Issue::Watch do
  let(:command) { described_class.new }
  let(:repository) { "owner/repo" }
  let(:watcher) { instance_double(Soba::Services::IssueWatcher) }

  before do
    allow(Soba::Services::IssueWatcher).to receive(:new).and_return(watcher)
    allow(watcher).to receive(:start)
  end

  describe "#execute" do
    context "with CLI arguments" do
      it "uses the interval from CLI arguments" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 30
        )

        command.execute(repository: repository, interval: 30, config: nil)
      end
    end

    context "with configuration file" do
      let(:config_path) { "spec/fixtures/config.yml" }

      before do
        allow(Soba::Configuration).to receive(:load!).with(path: config_path)
        allow(Soba::Configuration).to receive(:config).and_return(
          double(workflow: double(interval: 25))
        )
      end

      it "uses the interval from configuration when no CLI argument provided" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 25
        )

        command.execute(repository: repository, interval: nil, config: config_path)
      end

      it "prioritizes CLI argument over configuration" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 15
        )

        command.execute(repository: repository, interval: 15, config: config_path)
      end
    end

    context "with default values" do
      before do
        allow(Soba::Configuration).to receive(:config).and_return(
          double(workflow: double(interval: 20))
        )
      end

      it "uses default interval when no argument or config provided" do
        expect(watcher).to receive(:start).with(
          repository: repository,
          interval: 20
        )

        command.execute(repository: repository, interval: nil, config: nil)
      end
    end

    context "with dependency injection" do
      it "uses injected github client when provided" do
        github_client = instance_double(Soba::Infrastructure::GitHubClient)

        expect(Soba::Services::IssueWatcher).to receive(:new).
          with(github_client: github_client).
          and_return(watcher)

        command_with_client = described_class.new(github_client: github_client)
        command_with_client.execute(repository: repository, interval: 20, config: nil)
      end
    end

    context "error handling" do
      it "logs error when watcher fails" do
        error_message = "Connection failed"
        allow(watcher).to receive(:start).and_raise(StandardError, error_message)

        expect(command.logger).to receive(:error).with(
          "Failed to start issue watcher",
          hash_including(error: error_message)
        )

        expect do
          command.execute(repository: repository, interval: 20, config: nil)
        end.to raise_error(StandardError, error_message)
      end

      it "validates interval before starting" do
        expect do
          command.execute(repository: repository, interval: 5, config: nil)
        end.to raise_error(ArgumentError, /Interval must be at least/)
      end
    end
  end
end