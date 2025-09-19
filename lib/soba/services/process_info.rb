# frozen_string_literal: true

require 'English'
module Soba
  module Services
    class ProcessInfo
      attr_reader :pid

      def initialize(pid)
        @pid = pid.to_i
      end

      def memory_usage_mb
        return nil unless exists?

        memory_kb = if File.exist?("/proc/#{pid}/status")
                      # Linux: Read from /proc filesystem
                      memory_from_proc
                    else
                      # macOS/other: Use ps command
                      memory_from_ps
                    end

        memory_kb ? (memory_kb / 1024.0).round(2) : nil
      rescue StandardError
        nil
      end

      def exists?
        return false if pid <= 0

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      private

      def memory_from_proc
        content = File.read("/proc/#{pid}/status")
        # Look for VmRSS (Resident Set Size) in kilobytes
        if content =~ /VmRSS:\s+(\d+)\s+kB/
          Regexp.last_match(1).to_i
        end
      end

      def memory_from_ps
        # ps -o rss= returns memory in kilobytes
        output = `ps -o rss= -p #{pid} 2>/dev/null`.strip

        if $CHILD_STATUS.success? && !output.empty?
          output.to_i
        end
      end
    end
  end
end