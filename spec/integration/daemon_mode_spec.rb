# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe 'Daemon mode integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'soba.pid') }
  let(:log_file) { File.join(temp_dir, 'daemon.log') }

  before do
    allow(File).to receive(:expand_path).with('~/.soba/soba.pid').and_return(pid_file)
    allow(File).to receive(:expand_path).with('~/.soba/logs/daemon.log').and_return(log_file)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'daemon lifecycle' do
    it 'starts, checks status, and stops daemon' do
      # Load required components
      require_relative '../../lib/soba/services/pid_manager'
      require_relative '../../lib/soba/services/daemon_service'
      require_relative '../../lib/soba/commands/start'
      require_relative '../../lib/soba/commands/status'
      require_relative '../../lib/soba/commands/stop'

      # Initial state: no daemon running
      status_cmd = Soba::Commands::Status.new
      expect { status_cmd.execute }.to output(/No daemon process is running/).to_stdout

      # Start daemon (mock actual daemonization)
      pid_manager = Soba::Services::PidManager.new(pid_file)
      daemon_service = Soba::Services::DaemonService.new(
        pid_manager: pid_manager,
        log_file: log_file
      )

      # Simulate daemon start
      pid_manager.write(Process.pid)
      daemon_service.log("Daemon started successfully (PID: #{Process.pid})")
      daemon_service.log("Starting workflow monitor for test/repo")
      daemon_service.log("Polling interval: 10 seconds")

      # Check status - daemon should be running
      output = capture_stdout { status_cmd.execute }
      expect(output).to include("Daemon Status: Running")
      expect(output).to include("PID: #{Process.pid}")
      expect(output).to include("Daemon started successfully")

      # Stop daemon
      stop_cmd = Soba::Commands::Stop.new
      # Mock the kill behavior to simulate running -> terminated
      call_count = 0
      allow(Process).to receive(:kill) do |signal, pid|
        if pid == Process.pid
          call_count += 1
          case [signal, call_count]
          when [0, 1]
            1  # Process is running
          when ['TERM', 2]
            1  # SIGTERM sent
          when [0, 3], [0, 4], [0, 5]
            raise Errno::ESRCH # Process terminated
          else
            raise "Unexpected kill call: #{signal} #{call_count}"
          end
        end
      end

      output = capture_stdout { stop_cmd.execute }
      expect(output).to include("Daemon stopped successfully")

      # Verify daemon is stopped
      expect(File.exist?(pid_file)).to be false
    end

    it 'prevents duplicate daemon instances' do
      require_relative '../../lib/soba/services/pid_manager'
      require_relative '../../lib/soba/services/daemon_service'

      pid_manager = Soba::Services::PidManager.new(pid_file)
      daemon_service = Soba::Services::DaemonService.new(
        pid_manager: pid_manager,
        log_file: log_file
      )

      # Simulate first daemon
      pid_manager.write(Process.pid)

      # Try to start second daemon
      expect(daemon_service.already_running?).to be true
    end

    it 'handles stale PID files' do
      require_relative '../../lib/soba/services/pid_manager'
      require_relative '../../lib/soba/services/daemon_service'
      require_relative '../../lib/soba/commands/status'

      # Create stale PID file
      File.write(pid_file, '999999')

      status_cmd = Soba::Commands::Status.new
      output = capture_stdout { status_cmd.execute }
      expect(output).to include("Stale PID file found")
      expect(output).to include("999999")
    end
  end

  describe 'signal handling' do
    it 'responds to SIGTERM gracefully' do
      require_relative '../../lib/soba/services/pid_manager'
      require_relative '../../lib/soba/services/daemon_service'

      pid_manager = Soba::Services::PidManager.new(pid_file)
      daemon_service = Soba::Services::DaemonService.new(
        pid_manager: pid_manager,
        log_file: log_file
      )

      daemon_service.setup_signal_handlers do
        # Cleanup logic would go here
      end

      # Verify signal handlers are set up (can't easily test actual signal)
      expect { daemon_service.setup_signal_handlers {} }.not_to raise_error
    end
  end

  private

  def capture_stdout(&block)
    old_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end