# frozen_string_literal: true

require 'fileutils'
require 'time'

module Soba
  module Services
    class DaemonService
      attr_reader :pid_manager, :log_file

      def initialize(pid_manager:, log_file: nil)
        @pid_manager = pid_manager
        @log_file = log_file || File.expand_path('~/.soba/logs/daemon.log')
      end

      def already_running?
        if pid_manager.running?
          true
        else
          # Clean up stale PID file if exists
          pid_manager.cleanup_if_stale
          false
        end
      end

      def daemonize!
        # Fork and detach from terminal
        Process.daemon(true, false)

        # Write PID file
        pid_manager.write

        # Ensure log directory exists
        ensure_log_directory

        # Redirect stdout and stderr to log file
        redirect_output_to_log
      end

      def setup_signal_handlers(&cleanup_block)
        %w(TERM INT).each do |signal|
          Signal.trap(signal) do
            log "Received SIG#{signal}, shutting down gracefully..."
            cleanup_block&.call
            cleanup
            exit(0)
          end
        end
      end

      def cleanup
        log 'Cleaning up daemon...'
        pid_manager.delete
      end

      def log(message)
        ensure_log_directory
        timestamp = Time.now.strftime('[%Y-%m-%d %H:%M:%S]')
        File.open(log_file, 'a') do |f|
          f.puts "#{timestamp} #{message}"
          f.flush
        end
      rescue StandardError => e
        warn "Failed to write to log: #{e.message}"
      end

      def ensure_log_directory
        dir = File.dirname(log_file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      end

      private

      def redirect_output_to_log
        log_io = File.open(log_file, 'a')
        log_io.sync = true

        $stdout.reopen(log_io)
        $stderr.reopen(log_io)
      end
    end
  end
end