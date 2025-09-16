# frozen_string_literal: true

require "spec_helper"
require "open3"
require "timeout"

RSpec.describe "Issue Watch E2E", type: :e2e do
  let(:soba_bin) { File.expand_path("../../bin/soba", __dir__) }

  describe "soba issue watch" do
    context "with valid arguments" do
      it "starts watching with custom interval" do
        skip "Skipping E2E test that requires actual monitoring"
      end
    end

    context "with invalid arguments" do
      it "rejects interval less than minimum" do
        output, error, status = Open3.capture3(
          soba_bin,
          "issue",
          "watch",
          "owner/repo",
          "-i", "5"
        )

        expect(status.success?).to be false
        expect(error).to include("Interval must be at least")
      end

      it "requires repository argument" do
        output, error, status = Open3.capture3(
          soba_bin,
          "issue",
          "watch"
        )

        expect(status.success?).to be false
        expect(error).to include("repository is required")
      end
    end

    context "with configuration file" do
      let(:config_file) do
        Tempfile.new(["config", ".yml"]).tap do |f|
          f.write(<<~YAML)
            github:
              token: ${GITHUB_TOKEN}
              repository: douhashi/soba
            workflow:
              interval: 25
          YAML
          f.flush
        end
      end

      after do
        config_file.close
        config_file.unlink
      end

      it "uses interval from configuration file" do
        skip "Skipping E2E test that requires actual monitoring"
      end
    end

    describe "signal handling" do
      it "stops gracefully on SIGINT" do
        skip "Skipping E2E test that requires process management"
      end
    end
  end
end