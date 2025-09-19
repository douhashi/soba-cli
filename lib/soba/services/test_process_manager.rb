# frozen_string_literal: true

require 'securerandom'
require 'fileutils'
require_relative 'pid_manager'

module Soba
  module Services
    class TestProcessManager
      TEST_PID_DIR = '/tmp/soba-test-pids'

      def test_mode?
        ENV['SOBA_TEST_MODE'] == 'true'
      end

      def generate_test_session_name(repository)
        sanitized_repo = repository.gsub(/[\/._]/, '-')
        "soba-test-#{sanitized_repo}-#{generate_test_id}"
      end

      def generate_test_id
        "#{Process.pid}-#{SecureRandom.hex(4)}"
      end

      def test_pid_file_path(test_id)
        "#{TEST_PID_DIR}/#{test_id}.pid"
      end

      def create_test_pid_manager(test_id)
        pid_file = test_pid_file_path(test_id)
        PidManager.new(pid_file)
      end

      def cleanup_test_processes(test_id, timeout: 10)
        pid_manager = create_test_pid_manager(test_id)
        cleaned_processes = []

        pid = pid_manager.read
        return { success: true, cleaned_processes: cleaned_processes } unless pid

        if pid_manager.running?
          begin
            # Graceful termination
            Process.kill('TERM', pid)

            # Wait for graceful shutdown
            wait_time = 0
            while wait_time < timeout && pid_manager.running?
              sleep(0.1)
              wait_time += 0.1
            end

            # Force kill if still running
            if pid_manager.running?
              Process.kill('KILL', pid)
              sleep(0.1) # Brief wait for force kill
            end

            cleaned_processes << pid
          rescue Errno::ESRCH, Errno::EPERM
            # Process already dead or no permission
          end
        end

        # Clean up PID file
        pid_manager.delete

        { success: true, cleaned_processes: cleaned_processes }
      rescue StandardError => e
        { success: false, error: e.message, cleaned_processes: cleaned_processes }
      end

      def ensure_test_environment
        if test_mode?
          FileUtils.mkdir_p(TEST_PID_DIR)
        end

        { success: true, test_mode: test_mode? }
      rescue StandardError => e
        { success: false, error: e.message, test_mode: test_mode? }
      end
    end
  end
end