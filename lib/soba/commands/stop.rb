# frozen_string_literal: true

require 'fileutils'
require_relative '../services/pid_manager'
require_relative '../infrastructure/tmux_client'

module Soba
  module Commands
    class Stop
      def execute(_global_options = {}, options = {}, _args = [])
        # Allow test environment to override PID file path
        pid_file = ENV['SOBA_TEST_PID_FILE'] || File.expand_path('~/.soba/soba.pid')
        pid_manager = Soba::Services::PidManager.new(pid_file)

        pid = pid_manager.read

        unless pid
          puts "No daemon process is running"
          return 1
        end

        unless pid_manager.running?
          Soba.logger.info "Daemon was not running (stale PID file cleaned up)"
          pid_manager.delete
          return 0
        end

        puts "Stopping daemon (PID: #{pid})..."

        # Create stopping file for graceful shutdown
        stopping_file = File.expand_path('~/.soba/stopping')
        FileUtils.mkdir_p(File.dirname(stopping_file))
        FileUtils.touch(stopping_file)

        begin
          # Check if force option is specified
          if options[:force]
            # Force kill immediately
            Soba.logger.warn "Forcefully terminating daemon (PID: #{pid})"
            Process.kill('KILL', pid)
            sleep 1
            cleanup_tmux_sessions
            pid_manager.delete
            FileUtils.rm_f(stopping_file)
            Soba.logger.warn "Daemon forcefully terminated"
            return 0
          end

          # Send SIGTERM for graceful shutdown
          Process.kill('TERM', pid)
          Soba.logger.info "Sent SIGTERM signal, waiting for daemon to terminate"

          # Use custom timeout if specified
          timeout_value = options[:timeout] || 30

          # Wait for process to terminate gracefully
          if wait_for_termination(pid, timeout: timeout_value)
            Soba.logger.info "Daemon stopped successfully"
            cleanup_tmux_sessions
            pid_manager.delete
            FileUtils.rm_f(stopping_file)
            0
          else
            # Force kill if not terminated
            Soba.logger.warn "Daemon did not stop gracefully, forcefully terminating"
            Process.kill('KILL', pid)
            sleep 1
            cleanup_tmux_sessions
            pid_manager.delete
            FileUtils.rm_f(stopping_file)
            Soba.logger.warn "Daemon forcefully terminated"
            0
          end
        rescue Errno::ESRCH
          # Process doesn't exist
          Soba.logger.info "Process not found (already terminated)"
          pid_manager.delete
          FileUtils.rm_f(stopping_file)
          0
        rescue Errno::EPERM
          # Permission denied
          puts "Permission denied: unable to stop daemon (PID: #{pid})"
          puts "You may need to run this command with appropriate permissions"
          FileUtils.rm_f(stopping_file)
          1
        rescue StandardError => e
          Soba.logger.error "Error stopping daemon: #{e.message}"
          FileUtils.rm_f(stopping_file)
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

      def cleanup_tmux_sessions
        tmux_client = Soba::Infrastructure::TmuxClient.new
        repository = Soba::Configuration.config.github&.repository

        if repository
          # Kill only the current process's session
          session_name = "soba-#{repository.gsub(/[\/._]/, '-')}-#{Process.pid}"
          if tmux_client.session_exists?(session_name)
            Soba.logger.info "Cleaning up tmux session"
            if tmux_client.kill_session(session_name)
              Soba.logger.info "Killed tmux session: #{session_name}"
            else
              Soba.logger.warn "Failed to kill tmux session: #{session_name}"
            end
          end
        else
          # If no repository configured, try to clean up sessions with current PID
          sessions = tmux_client.list_soba_sessions.select { |s| s.end_with?("-#{Process.pid}") }
          unless sessions.empty?
            Soba.logger.info "Cleaning up tmux sessions"
            sessions.each do |session|
              if tmux_client.kill_session(session)
                Soba.logger.info "Killed tmux session: #{session}"
              else
                Soba.logger.warn "Failed to kill tmux session: #{session}"
              end
            end
          end
        end
      rescue StandardError => e
        Soba.logger.warn "Failed to cleanup tmux sessions: #{e.message}"
      end
    end
  end
end