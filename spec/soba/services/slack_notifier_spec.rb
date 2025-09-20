# frozen_string_literal: true

require "spec_helper"
require "soba/services/slack_notifier"

RSpec.describe Soba::Services::SlackNotifier do
  let(:webhook_url) { "https://hooks.slack.com/services/TEST/WEBHOOK/URL" }
  let(:notifier) { described_class.new(webhook_url: webhook_url) }
  let(:issue_data) do
    {
      number: 134,
      title: "sobaが管理する各フェーズの実行時にslack通知をしたい",
      phase: "plan",
    }
  end

  describe "#initialize" do
    context "with valid webhook_url" do
      it "creates an instance successfully" do
        expect(notifier).to be_a(described_class)
      end
    end

    context "with nil webhook_url" do
      it "creates an instance with nil webhook_url" do
        notifier = described_class.new(webhook_url: nil)
        expect(notifier.instance_variable_get(:@webhook_url)).to be_nil
      end
    end

    context "with empty webhook_url" do
      it "creates an instance with empty webhook_url" do
        notifier = described_class.new(webhook_url: "")
        expect(notifier.instance_variable_get(:@webhook_url)).to eq("")
      end
    end
  end

  describe "#notify_phase_start" do
    context "when webhook_url is configured" do
      let(:connection_stub) { instance_double(Faraday::Connection) }
      let(:response_stub) { instance_double(Faraday::Response, status: 200, success?: true) }

      before do
        allow(Faraday).to receive(:new).and_return(connection_stub)
        allow(connection_stub).to receive(:post).and_return(response_stub)
      end

      it "sends a notification successfully" do
        expect(connection_stub).to receive(:post) do |url, payload|
          expect(url).to eq(webhook_url)

          json_payload = JSON.parse(payload)
          expect(json_payload["text"]).to include("Issue #134")
          expect(json_payload["attachments"].first["title"]).to include("sobaが管理する各フェーズの実行時にslack通知をしたい")

          fields = json_payload["attachments"].first["fields"]
          phase_field = fields.find { |f| f["title"] == "Phase" }
          expect(phase_field["value"]).to eq("plan")

          response_stub
        end

        result = notifier.notify_phase_start(issue_data)
        expect(result).to be true
      end

      it "includes attachments with phase details" do
        expect(connection_stub).to receive(:post) do |url, payload|
          json_payload = JSON.parse(payload)
          expect(json_payload["attachments"]).to be_an(Array)
          expect(json_payload["attachments"].first).to include(
            "color" => "good",
            "fields" => be_an(Array)
          )

          fields = json_payload["attachments"].first["fields"]
          expect(fields).to include(
            hash_including("title" => "Issue", "value" => "#134"),
            hash_including("title" => "Phase", "value" => "plan"),
            hash_including("title" => "Title", "value" => "sobaが管理する各フェーズの実行時にslack通知をしたい")
          )

          response_stub
        end

        notifier.notify_phase_start(issue_data)
      end

      context "when HTTP request fails" do
        let(:error_response) { instance_double(Faraday::Response, status: 500, success?: false) }

        before do
          allow(connection_stub).to receive(:post).and_return(error_response)
        end

        it "returns false" do
          result = notifier.notify_phase_start(issue_data)
          expect(result).to be false
        end

        it "logs an error message" do
          logger = instance_double(Logger)
          allow(notifier).to receive(:logger).and_return(logger)
          expect(logger).to receive(:error).with(/Failed to send Slack notification/)

          notifier.notify_phase_start(issue_data)
        end
      end

      context "when network error occurs" do
        before do
          allow(connection_stub).to receive(:post).and_raise(Faraday::ConnectionFailed.new("Connection failed"))
        end

        it "returns false" do
          result = notifier.notify_phase_start(issue_data)
          expect(result).to be false
        end

        it "logs the error" do
          logger = instance_double(Logger)
          allow(notifier).to receive(:logger).and_return(logger)
          expect(logger).to receive(:error).with(/Error sending Slack notification/)

          notifier.notify_phase_start(issue_data)
        end
      end
    end

    context "when webhook_url is not configured" do
      let(:notifier) { described_class.new(webhook_url: nil) }

      it "returns false without making HTTP request" do
        expect(Faraday).not_to receive(:new)

        result = notifier.notify_phase_start(issue_data)
        expect(result).to be false
      end

      it "returns false without logging" do
        result = notifier.notify_phase_start(issue_data)
        expect(result).to be false
      end
    end

    context "when webhook_url is empty" do
      let(:notifier) { described_class.new(webhook_url: "") }

      it "returns false without making HTTP request" do
        expect(Faraday).not_to receive(:new)

        result = notifier.notify_phase_start(issue_data)
        expect(result).to be false
      end
    end
  end

  describe "#enabled?" do
    context "with valid webhook_url" do
      it "returns true" do
        expect(notifier.enabled?).to be true
      end
    end

    context "with nil webhook_url" do
      let(:notifier) { described_class.new(webhook_url: nil) }

      it "returns false" do
        expect(notifier.enabled?).to be false
      end
    end

    context "with empty webhook_url" do
      let(:notifier) { described_class.new(webhook_url: "") }

      it "returns false" do
        expect(notifier.enabled?).to be false
      end
    end
  end

  describe ".from_env" do
    context "when SLACK_WEBHOOK_URL is set" do
      before do
        ENV["SLACK_WEBHOOK_URL"] = webhook_url
      end

      after do
        ENV.delete("SLACK_WEBHOOK_URL")
      end

      it "creates an instance with webhook_url from environment" do
        notifier = described_class.from_env
        expect(notifier.instance_variable_get(:@webhook_url)).to eq(webhook_url)
      end
    end

    context "when SLACK_WEBHOOK_URL is not set" do
      before do
        ENV.delete("SLACK_WEBHOOK_URL")
      end

      it "creates an instance with nil webhook_url" do
        notifier = described_class.from_env
        expect(notifier.instance_variable_get(:@webhook_url)).to be_nil
      end
    end
  end
end