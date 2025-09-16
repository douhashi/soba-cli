# frozen_string_literal: true

require "spec_helper"
require "soba/services/issue_watcher"

RSpec.describe Soba::Services::IssueWatcher do
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:watcher) { described_class.new(github_client: github_client) }
  let(:repository) { "owner/repo" }
  let(:interval) { 1 }

  let(:issues) do
    [
      Soba::Domain::Issue.new(
        id: 1,
        number: 123,
        title: "Fix bug",
        state: "open",
        labels: [{ name: "bug", color: "ff0000" }],
        updated_at: Time.now - 3600
      ),
      Soba::Domain::Issue.new(
        id: 2,
        number: 124,
        title: "Add feature",
        state: "open",
        labels: [{ name: "feature", color: "00ff00" }],
        updated_at: Time.now
      ),
    ]
  end

  describe "#start" do
    before do
      allow(github_client).to receive(:issues).and_return(issues)
      allow(watcher).to receive(:setup_signal_handlers)
      allow(watcher).to receive(:sleep)
    end

    context "when starting the watcher" do
      it "logs the start message" do
        expect(Soba.logger).to receive(:info).with(
          "Starting issue watcher",
          repository: repository,
          interval: interval
        )

        allow(watcher).to receive(:running?).and_return(false)
        watcher.start(repository: repository, interval: interval)
      end

      it "fetches issues at the specified interval" do
        expect(github_client).to receive(:issues).with(repository, state: "open").at_least(:once)

        allow(watcher).to receive(:running?).and_return(true, false)
        watcher.start(repository: repository, interval: interval)
      end
    end

    context "when displaying issues" do
      it "displays issue information in a formatted way" do
        allow(watcher).to receive(:running?).and_return(true, false)

        expect { watcher.start(repository: repository, interval: interval) }.
          to output(/Fix bug/).
          to_stdout
      end

      it "shows the issue count" do
        allow(watcher).to receive(:running?).and_return(true, false)

        expect { watcher.start(repository: repository, interval: interval) }.
          to output(/Found 2 open issues/).
          to_stdout
      end
    end

    context "when handling errors" do
      it "continues running when network error occurs" do
        call_count = 0
        allow(github_client).to receive(:issues) do
          call_count += 1
          if call_count == 1
            raise Soba::Infrastructure::NetworkError, "Connection failed"
          else
            issues
          end
        end

        allow(watcher).to receive(:running?).and_return(true, true, false)

        expect(Soba.logger).to receive(:error).with(
          "Failed to fetch issues",
          hash_including(error: "Connection failed")
        )

        watcher.start(repository: repository, interval: interval)
      end
    end
  end

  describe "#stop" do
    it "stops the watcher gracefully" do
      expect(Soba.logger).to receive(:info).with("Stopping issue watcher...")

      watcher.stop
      expect(watcher).not_to be_running
    end
  end

  describe "signal handling" do
    it "registers SIGINT handler" do
      expect(Signal).to receive(:trap).with("INT")
      expect(Signal).to receive(:trap).with("TERM")

      watcher.send(:setup_signal_handlers)
    end
  end
end