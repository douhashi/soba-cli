# frozen_string_literal: true

require "spec_helper"
require "soba/services/session_resolver"
require "soba/services/pid_manager"
require "soba/services/tmux_session_manager"

RSpec.describe Soba::Services::SessionResolver do
  let(:repository) { "test-repo" }
  let(:pid_manager) { instance_double(Soba::Services::PidManager) }
  let(:tmux_manager) { instance_double(Soba::Services::TmuxSessionManager) }
  let(:resolver) { described_class.new(pid_manager: pid_manager, tmux_manager: tmux_manager) }

  describe "#resolve_active_session" do
    context "when PID file exists with valid PID" do
      let(:pid) { 12345 }
      let(:expected_session_name) { "soba-test-repo-12345" }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(tmux_manager).to receive(:session_exists?).with(expected_session_name).and_return(true)
      end

      it "returns the session name based on PID" do
        expect(resolver.resolve_active_session(repository)).to eq(expected_session_name)
      end
    end

    context "when PID file exists but session does not exist" do
      let(:pid) { 12345 }
      let(:session_name) { "soba-test-repo-12345" }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(pid_manager).to receive(:delete)
        allow(tmux_manager).to receive(:session_exists?).with(session_name).and_return(false)
      end

      it "returns nil" do
        expect(resolver.resolve_active_session(repository)).to be_nil
      end

      it "cleans up the stale PID file" do
        expect(pid_manager).to receive(:delete)
        resolver.resolve_active_session(repository)
      end
    end

    context "when PID file does not exist" do
      before do
        allow(pid_manager).to receive(:read).and_return(nil)
      end

      it "returns nil" do
        expect(resolver.resolve_active_session(repository)).to be_nil
      end
    end

    # Multiple PID files test removed - not supported with current PidManager

    context "when error occurs reading PID file" do
      before do
        allow(pid_manager).to receive(:read).and_raise(Errno::EACCES, "Permission denied")
      end

      it "raises the error" do
        expect { resolver.resolve_active_session(repository) }.to raise_error(Errno::EACCES)
      end
    end
  end

  describe "#find_all_repository_sessions" do
    context "when session exists" do
      let(:pid) { 12345 }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(tmux_manager).to receive(:session_exists?).with("soba-test-repo-12345").and_return(true)
      end

      it "returns session with active status" do
        result = resolver.find_all_repository_sessions(repository)
        expect(result).to eq([
          { name: "soba-test-repo-12345", pid: 12345, active: true }
        ])
      end
    end

    context "when session does not exist" do
      let(:pid) { 12345 }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(pid_manager).to receive(:delete)
        allow(tmux_manager).to receive(:session_exists?).with("soba-test-repo-12345").and_return(false)
      end

      it "returns session with inactive status" do
        result = resolver.find_all_repository_sessions(repository)
        expect(result).to eq([
          { name: "soba-test-repo-12345", pid: 12345, active: false }
        ])
      end

      it "cleans up stale PID files" do
        expect(pid_manager).to receive(:delete)
        resolver.find_all_repository_sessions(repository)
      end
    end

    context "when no PID files exist" do
      before do
        allow(pid_manager).to receive(:read).and_return(nil)
      end

      it "returns empty array" do
        expect(resolver.find_all_repository_sessions(repository)).to eq([])
      end
    end
  end

  describe "#generate_session_name" do
    it "generates session name with repository and PID" do
      expect(resolver.generate_session_name(repository, 12345)).to eq("soba-test-repo-12345")
    end

    it "handles repository names with special characters" do
      expect(resolver.generate_session_name("my.repo-name", 12345)).to eq("soba-my-repo-name-12345")
    end

    it "handles nil PID" do
      expect { resolver.generate_session_name(repository, nil) }.to raise_error(ArgumentError, "PID cannot be nil")
    end
  end

  describe "#cleanup_stale_sessions" do
    context "when session exists" do
      let(:pid) { 12345 }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(tmux_manager).to receive(:session_exists?).with("soba-test-repo-12345").and_return(true)
      end

      it "returns empty array" do
        expect(pid_manager).not_to receive(:delete)
        cleaned = resolver.cleanup_stale_sessions(repository)
        expect(cleaned).to eq([])
      end
    end

    context "when session does not exist" do
      let(:pid) { 12345 }

      before do
        allow(pid_manager).to receive(:read).and_return(pid)
        allow(tmux_manager).to receive(:session_exists?).with("soba-test-repo-12345").and_return(false)
      end

      it "removes PID file and returns the PID" do
        expect(pid_manager).to receive(:delete)
        cleaned = resolver.cleanup_stale_sessions(repository)
        expect(cleaned).to eq([pid])
      end
    end

    context "when no PID file exists" do
      before do
        allow(pid_manager).to receive(:read).and_return(nil)
      end

      it "returns empty array" do
        expect(pid_manager).not_to receive(:delete)
        cleaned = resolver.cleanup_stale_sessions(repository)
        expect(cleaned).to eq([])
      end
    end
  end
end