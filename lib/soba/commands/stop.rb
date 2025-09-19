# frozen_string_literal: true

require_relative '../services/pid_manager'

module Soba
  module Commands
    class Stop
      def execute(_global_options = {}, _options = {}, _args = [])
        # Allow test environment to override PID file path
        pid_file = ENV['SOBA_TEST_PID_FILE'] || File.expand_path('~/.soba/soba.pid')
        pid_manager = Soba::Services::PidManager.new(pid_file)

        pid = pid_manager.read

        unless pid
          puts "No daemon process is running"
          return 1
        end

        unless pid_manager.running?
          puts "Daemon was not running (stale PID file cleaned up)"
          pid_manager.delete
          return 0
        end

        puts "Stopping daemon (PID: #{pid})..."

        begin
          # Send SIGTERM for graceful shutdown
          Process.kill('TERM', pid)
          puts "Sent SIGTERM signal, waiting for daemon to terminate..."

          # Wait for process to terminate gracefully
          if wait_for_termination(pid, timeout: 30)
            puts "Daemon stopped successfully"
            pid_manager.delete
            0
          else
            # Force kill if not terminated
            puts "Daemon did not stop gracefully, forcefully terminating..."
            Process.kill('KILL', pid)
            sleep 1
            pid_manager.delete
            puts "Daemon forcefully terminated"
            0
          end
        rescue Errno::ESRCH
          # Process doesn't exist
          puts "Process not found (already terminated)"
          pid_manager.delete
          0
        rescue Errno::EPERM
          # Permission denied
          puts "Permission denied: unable to stop daemon (PID: #{pid})"
          puts "You may need to run this command with appropriate permissions"
          1
        rescue StandardError => e
          puts "Error stopping daemon: #{e.message}"
          1
        end
      end

      private

      def wait_for_termination(pid, timeout: 30)
        deadline = Time.now + timeout

        while Time.now < deadline
          begin
            # Check if process still exists
            Process.kill(0, pid)
            sleep 0.5
          rescue Errno::ESRCH
            # Process no longer exists
            return true
          end
        end

        false
      end
    end
  end
end