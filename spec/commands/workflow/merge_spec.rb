# frozen_string_literal: true

require "spec_helper"
require "soba/commands/workflow/merge"
require "soba/services/auto_merge_service"

RSpec.describe Soba::Commands::Workflow::Merge do
  let(:command) { described_class.new }
  let(:auto_merge_service) { instance_double(Soba::Services::AutoMergeService) }
  let(:config) do
    double("Config", github: double("GitHub", repository: "owner/repo"))
  end

  before do
    allow(Soba::Configuration).to receive(:load!)
    allow(Soba::Configuration).to receive(:config).and_return(config)
    allow(Soba::Services::AutoMergeService).to receive(:new).and_return(auto_merge_service)
  end

  describe "#execute" do
    context "when merge is successful" do
      let(:result) do
        {
          merged_count: 2,
          failed_count: 0,
          details: {
            merged: [
              { number: 10, title: "Feature PR", sha: "abc123" },
              { number: 15, title: "Bug fix PR", sha: "def456" },
            ],
            failed: [],
          },
        }
      end

      before do
        allow(auto_merge_service).to receive(:execute).and_return(result)
      end

      it "displays success message with details" do
        expect { command.execute }.to output(/Auto-merge completed successfully/).to_stdout
        expect { command.execute }.to output(/Merged: 2 PRs/).to_stdout
        expect { command.execute }.to output(/#10: Feature PR/).to_stdout
        expect { command.execute }.to output(/#15: Bug fix PR/).to_stdout
      end
    end

    context "when some PRs fail to merge" do
      let(:result) do
        {
          merged_count: 1,
          failed_count: 1,
          details: {
            merged: [
              { number: 10, title: "Feature PR", sha: "abc123" },
            ],
            failed: [
              { number: 15, title: "Bug fix PR", reason: "Merge conflict" },
            ],
          },
        }
      end

      before do
        allow(auto_merge_service).to receive(:execute).and_return(result)
      end

      it "displays partial success with details" do
        expect { command.execute }.to output(/Auto-merge completed with some failures/).to_stdout
        expect { command.execute }.to output(/Merged: 1 PRs/).to_stdout
        expect { command.execute }.to output(/Failed: 1 PRs/).to_stdout
        expect { command.execute }.to output(/#15: Bug fix PR - Merge conflict/).to_stdout
      end
    end

    context "when no PRs are found" do
      let(:result) do
        {
          merged_count: 0,
          failed_count: 0,
          details: {
            merged: [],
            failed: [],
          },
        }
      end

      before do
        allow(auto_merge_service).to receive(:execute).and_return(result)
      end

      it "displays no PRs found message" do
        expect { command.execute }.to output(/No PRs with soba:lgtm label found/).to_stdout
      end
    end

    context "when an error occurs" do
      before do
        allow(auto_merge_service).to receive(:execute).and_raise(StandardError.new("API error"))
      end

      it "displays error message" do
        expect { command.execute }.to output(/Error: API error/).to_stdout
      end
    end
  end
end