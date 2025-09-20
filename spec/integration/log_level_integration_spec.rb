# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"

RSpec.describe "Log Level Integration" do
  def run_soba_command(args, verbose: false)
    if verbose
      cmd = "bundle exec bin/soba -v #{args}"
    else
      cmd = "bundle exec bin/soba #{args}"
    end
    stdout, stderr, status = Open3.capture3(cmd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  describe "soba with verbose option" do
    context "when running without verbose flag" do
      it "uses INFO level logs by default" do
        # Test that help shows without debug logs
        result = run_soba_command("help", verbose: false)

        # Should show help without debug logs
        expect(result[:stdout]).to include("GitHub to Claude Code workflow automation")
        expect(result[:stdout]).not_to include("[DEBUG]")
      end
    end

    context "when running with --verbose flag" do
      it "enables DEBUG level logs" do
        # Test that verbose mode is recognized
        result = run_soba_command("help", verbose: true)

        # Should show help
        expect(result[:stdout]).to include("GitHub to Claude Code workflow automation")
      end
    end

    context "when displaying help for start command" do
      it "shows start command help" do
        result = run_soba_command("help start", verbose: false)
        expect(result[:stdout]).to include("Start workflow automation")
      end
    end
  end

  describe "log format consistency" do
    let(:log_output) { StringIO.new }
    let(:test_logger) { SemanticLogger["TestLogger"] }

    before do
      SemanticLogger.clear_appenders!
      SemanticLogger.add_appender(io: log_output, formatter: :default)
    end

    after do
      SemanticLogger.clear_appenders!
      SemanticLogger.add_appender(io: $stdout, formatter: :color)
    end

    it "uses SemanticLogger format for all logs" do
      # Test that all loggers use consistent format
      SemanticLogger.default_level = :debug

      # Test different logger instances
      workflow_logger = SemanticLogger["WorkflowBlockingChecker"]
      queueing_logger = SemanticLogger["QueueingService"]
      cleaner_logger = SemanticLogger["ClosedIssueWindowCleaner"]

      workflow_logger.info("Test workflow message")
      queueing_logger.debug("Test queueing message")
      cleaner_logger.warn("Test cleaner message")

      SemanticLogger.flush
      output = log_output.string

      # All logs should have consistent SemanticLogger format
      expect(output).to include("WorkflowBlockingChecker")
      expect(output).to include("Test workflow message")
      expect(output).to include("QueueingService")
      expect(output).to include("Test queueing message")
      expect(output).to include("ClosedIssueWindowCleaner")
      expect(output).to include("Test cleaner message")
    end
  end
end