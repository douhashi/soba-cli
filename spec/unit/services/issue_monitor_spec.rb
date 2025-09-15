# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Services::IssueMonitor do
  let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
  let(:monitor) { described_class.new(github_client: github_client) }

  describe "#monitor" do
    let(:issues) { [double("issue")] }

    before do
      allow(github_client).to receive(:issues).and_return(issues)
      allow(monitor).to receive(:sleep)
    end

    it "fetches issues repeatedly" do
      expect(github_client).to receive(:issues).with("owner/repo").at_least(:twice)

      thread = Thread.new { monitor.monitor(repository: "owner/repo", interval: 1) }
      sleep 0.1
      thread.kill
    end

    context "when fetching issues fails" do
      before do
        allow(github_client).to receive(:issues).and_raise(StandardError.new("API Error"))
      end

      it "logs error and continues" do
        expect(Soba.logger).to receive(:error).with(/Failed to fetch issues/).at_least(:once)

        thread = Thread.new { monitor.monitor(repository: "owner/repo", interval: 1) }
        sleep 0.1
        thread.kill
      end
    end
  end
end