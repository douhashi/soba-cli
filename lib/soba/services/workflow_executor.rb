# frozen_string_literal: true

require 'open3'

module Soba
  module Services
    class WorkflowExecutionError < StandardError; end

    class WorkflowExecutor
      def execute(phase:, issue_number:)
        return nil unless phase.command

        command_array = build_command(phase, issue_number)

        stdout, stderr, status = Open3.popen3(*command_array) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          [stdout.read, stderr.read, wait_thr.value]
        end

        {
          success: status.exitstatus == 0,
          output: stdout,
          error: stderr,
          exit_code: status.exitstatus,
        }
      rescue Errno::ENOENT => e
        raise WorkflowExecutionError, "Failed to execute workflow command: #{e.message}"
      rescue StandardError => e
        raise WorkflowExecutionError, "Failed to execute workflow command: #{e.message}"
      end

      private

      def build_command(phase_config, issue_number)
        command = [phase_config.command]
        command.concat(phase_config.options) if phase_config.options&.any?

        if phase_config.parameter
          parameter = phase_config.parameter.gsub('{{issue-number}}', issue_number.to_s)
          command << parameter
        end

        command
      end
    end
  end
end