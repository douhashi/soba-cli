# frozen_string_literal: true

require 'fileutils'
require 'timeout'

module Soba
  module Infrastructure
    class LockTimeoutError < StandardError; end

    class LockManager
      DEFAULT_TIMEOUT = 5 # seconds
      DEFAULT_STALE_THRESHOLD = 300 # 5 minutes
      RETRY_INTERVAL = 0.1 # seconds

      def initialize(lock_directory: nil)
        @lock_directory = lock_directory || default_lock_directory
        ensure_lock_directory_exists
      end

      def acquire_lock(resource_name, timeout: 0, stale_threshold: DEFAULT_STALE_THRESHOLD)
        lock_file = lock_file_path(resource_name)
        deadline = Time.now + timeout if timeout > 0

        loop do
          # Check for stale lock
          if File.exist?(lock_file) && stale_threshold > 0
            begin
              if Time.now - File.mtime(lock_file) > stale_threshold
                # Remove stale lock
                File.delete(lock_file)
              end
            rescue Errno::ENOENT
              # File was deleted by another process, continue
            rescue
              # Other errors, ignore and continue
            end
          end

          # Try to acquire lock
          begin
            File.open(lock_file, File::WRONLY | File::CREAT | File::EXCL) do |f|
              f.write(Process.pid.to_s)
            end
            return true
          rescue Errno::EEXIST
            # Lock already exists
            if timeout > 0 && Time.now < deadline
              sleep RETRY_INTERVAL
              next
            else
              return false
            end
          end
        end
      end

      def release_lock(resource_name)
        lock_file = lock_file_path(resource_name)

        return false unless File.exist?(lock_file)

        # Check if we own the lock
        begin
          pid = File.read(lock_file).strip.to_i
          if pid == Process.pid
            File.delete(lock_file)
            return true
          end
        rescue Errno::ENOENT
          # File was already deleted
          return false
        rescue StandardError
          # Error reading file
        end

        false
      end

      def with_lock(resource_name, timeout: DEFAULT_TIMEOUT, stale_threshold: DEFAULT_STALE_THRESHOLD)
        unless acquire_lock(resource_name, timeout: timeout, stale_threshold: stale_threshold)
          raise LockTimeoutError, "Failed to acquire lock for #{resource_name} within #{timeout} seconds"
        end

        begin
          yield
        ensure
          release_lock(resource_name)
        end
      end

      def locked?(resource_name)
        lock_file = lock_file_path(resource_name)
        File.exist?(lock_file)
      end

      def cleanup_stale_locks(threshold: DEFAULT_STALE_THRESHOLD)
        return [] unless Dir.exist?(@lock_directory)

        removed = []
        Dir.glob(File.join(@lock_directory, '*.lock')).each do |lock_file|
          if Time.now - File.mtime(lock_file) > threshold
            begin
              File.delete(lock_file)
            rescue
              nil
            end
            removed << File.basename(lock_file, '.lock')
          end
        end

        removed
      end

      private

      def default_lock_directory
        File.join(Dir.tmpdir, 'soba-locks')
      end

      def ensure_lock_directory_exists
        FileUtils.mkdir_p(@lock_directory) unless Dir.exist?(@lock_directory)
      end

      def lock_file_path(resource_name)
        File.join(@lock_directory, "#{resource_name}.lock")
      end
    end
  end
end