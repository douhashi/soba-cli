# frozen_string_literal: true

require 'time'
require 'json'
require_relative '../services/pid_manager'
require_relative '../services/status_manager'
require_relative '../services/process_info'

module Soba
  module Commands
    class Status
      def execute(_global_options = {}, options = {}, _args = [])
        # Allow test environment to override paths
        pid_file = ENV['SOBA_TEST_PID_FILE'] || File.expand_path('~/.soba/soba.pid')
        log_file = ENV['SOBA_TEST_LOG_FILE'] || File.expand_path('~/.soba/logs/daemon.log')
        status_file = ENV['SOBA_TEST_STATUS_FILE'] || File.expand_path('~/.soba/status.json')

        pid_manager = Soba::Services::PidManager.new(pid_file)
        status_manager = Soba::Services::StatusManager.new(status_file)
        pid = pid_manager.read

        # JSON出力の場合
        if options[:json]
          output_json(pid_manager, status_manager, log_file, pid, options)
          return 0
        end

        # 通常のテキスト出力
        output_text(pid_manager, status_manager, log_file, pid, options)
      end

      private

      def output_text(pid_manager, status_manager, log_file, pid, options)
        puts "=" * 50
        puts "Soba Daemon Status"
        puts "=" * 50

        status_data = status_manager.read

        if pid_manager.running?
          puts "Daemon Status: Running"
          puts "PID: #{pid}"

          # Try to get process start time and memory usage
          begin
            # Get file creation time as approximation
            pid_file_path = File.expand_path('~/.soba/soba.pid')
            if File.exist?(pid_file_path)
              start_time = File.ctime(pid_file_path)
              uptime = Time.now - start_time
              puts "Started: #{start_time.strftime('%Y-%m-%d %H:%M:%S')}"
              puts "Uptime: #{format_uptime(uptime)}"
            end

            # Get memory usage
            process_info = Soba::Services::ProcessInfo.new(pid)
            memory_mb = process_info.memory_usage_mb
            memory_mb ||= status_data[:memory_mb] if status_data
            puts "Memory Usage: #{memory_mb} MB" if memory_mb
          rescue StandardError
            # Ignore errors getting process info
          end

          # Display current Issue and last processed
          if status_data
            if status_data[:current_issue]
              issue = status_data[:current_issue]
              puts "\nCurrent Issue: ##{issue[:number]} (#{issue[:phase]})"
            end

            if status_data[:last_processed]
              last = status_data[:last_processed]
              puts "Last Processed: ##{last[:number]} (completed at #{last[:completed_at]})"
            end
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
            # Get specified number of log lines
            num_lines = options[:log] || 10
            log_lines = File.readlines(log_file).last(num_lines)
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

      def output_json(pid_manager, status_manager, log_file, pid, options)
        status_data = status_manager.read || {}
        result = {}

        if pid_manager.running?
          pid_file_path = File.expand_path('~/.soba/soba.pid')
          daemon_info = {
            status: 'running',
            pid: pid,
          }

          # Add start time and uptime
          if File.exist?(pid_file_path)
            start_time = File.ctime(pid_file_path)
            uptime = Time.now - start_time
            daemon_info[:started_at] = start_time.iso8601
            daemon_info[:uptime_seconds] = uptime.to_i
          end

          # Add memory usage
          process_info = Soba::Services::ProcessInfo.new(pid)
          memory_mb = process_info.memory_usage_mb || status_data[:memory_mb]
          daemon_info[:memory_mb] = memory_mb if memory_mb

          result[:daemon] = daemon_info
        else
          result[:daemon] = { status: 'not_running' }
        end

        # Add current Issue info
        if status_data[:current_issue]
          result[:current_issue] = status_data[:current_issue]
        end

        # Add last processed info
        if status_data[:last_processed]
          result[:last_processed] = status_data[:last_processed]
        end

        # Add logs
        if File.exist?(log_file) && File.size(log_file) > 0
          num_lines = options[:log] || 10
          log_lines = File.readlines(log_file).last(num_lines)
          result[:logs] = log_lines.map(&:chomp)
        else
          result[:logs] = []
        end

        puts JSON.pretty_generate(result)
      end

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