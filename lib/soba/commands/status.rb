# frozen_string_literal: true

require 'time'
require_relative '../services/pid_manager'

module Soba
  module Commands
    class Status
      def execute(_global_options = {}, _options = {}, _args = [])
        pid_file = File.expand_path('~/.soba/soba.pid')
        log_file = File.expand_path('~/.soba/logs/daemon.log')

        pid_manager = Soba::Services::PidManager.new(pid_file)
        pid = pid_manager.read

        puts "=" * 50
        puts "Soba Daemon Status"
        puts "=" * 50

        if pid_manager.running?
          puts "Daemon Status: Running"
          puts "PID: #{pid}"

          # Try to get process start time
          begin
            # Get file creation time as approximation
            if File.exist?(pid_file)
              start_time = File.ctime(pid_file)
              uptime = Time.now - start_time
              puts "Started: #{start_time.strftime('%Y-%m-%d %H:%M:%S')}"
              puts "Uptime: #{format_uptime(uptime)}"
            end
          rescue StandardError
            # Ignore errors getting process info
          end
        elsif pid
          puts "Daemon Status: Not running"
          puts "Stale PID file found (PID: #{pid})"
          puts "Run 'soba start' to start the daemon"
          return 1
        else
          puts "No daemon process is running"
          puts "Run 'soba start' to start the daemon"
          return 0
        end

        puts ""
        puts "Recent Log Output:"
        puts "-" * 50

        if File.exist?(log_file)
          if File.size(log_file) > 0
            # Get last 10 lines of log
            log_lines = File.readlines(log_file).last(10)
            log_lines.each { |line| puts line.chomp }
          else
            puts "Log file is empty"
          end
        else
          puts "No log file found at #{log_file}"
        end

        puts "=" * 50

        0
      end

      private

      def format_uptime(seconds)
        days = (seconds / 86400).to_i
        hours = ((seconds % 86400) / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i

        parts = []
        parts << "#{days}d" if days > 0
        parts << "#{hours}h" if hours > 0
        parts << "#{minutes}m" if minutes > 0 || parts.empty?

        parts.join(' ')
      end
    end
  end
end