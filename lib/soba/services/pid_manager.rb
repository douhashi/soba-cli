# frozen_string_literal: true

require 'fileutils'
require 'timeout'

module Soba
  module Services
    class PidManager
      attr_reader :pid_file

      def initialize(pid_file)
        @pid_file = pid_file
      end

      def write(pid = Process.pid)
        ensure_directory_exists
        File.open(pid_file, 'w') do |f|
          f.flock(File::LOCK_EX)
          f.write(pid.to_s)
          f.flush
        end
      end

      def read
        return nil unless File.exist?(pid_file)

        content = File.read(pid_file).strip
        return nil if content.empty?

        pid = content.to_i
        return nil if pid <= 0

        pid
      rescue StandardError
        nil
      end

      def delete
        return false unless File.exist?(pid_file)

        File.delete(pid_file)
        true
      rescue StandardError
        false
      end

      def running?
        pid = read
        return false unless pid

        # Check if process exists
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def cleanup_if_stale
        return false unless File.exist?(pid_file)

        if running?
          false
        else
          delete
          true
        end
      end

      def lock(timeout: 5)
        ensure_directory_exists
        Timeout.timeout(timeout) do
          File.open(pid_file, File::CREAT | File::WRONLY) do |f|
            f.flock(File::LOCK_EX)
            yield if block_given?
          end
        end
      end

      private

      def ensure_directory_exists
        dir = File.dirname(pid_file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      end
    end
  end
end