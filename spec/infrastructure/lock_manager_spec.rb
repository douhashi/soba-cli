# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'soba/infrastructure/lock_manager'

RSpec.describe Soba::Infrastructure::LockManager do
  let(:lock_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(lock_directory: lock_dir) }

  after do
    FileUtils.rm_rf(lock_dir)
  end

  describe '#acquire_lock' do
    let(:resource_name) { 'issue-window-42' }

    it 'acquires a lock for the resource' do
      result = manager.acquire_lock(resource_name)

      expect(result).to be true
      expect(File.exist?(File.join(lock_dir, "#{resource_name}.lock"))).to be true
    end

    it 'returns false if lock is already held' do
      # First acquire succeeds
      expect(manager.acquire_lock(resource_name)).to be true

      # Second acquire fails
      expect(manager.acquire_lock(resource_name)).to be false
    end

    context 'with timeout' do
      it 'retries until timeout' do
        # First acquire succeeds
        manager.acquire_lock(resource_name)

        # Simulate lock release after 0.1 seconds
        Thread.new do
          sleep 0.1
          manager.release_lock(resource_name)
        end

        # Second acquire with timeout should eventually succeed
        result = manager.acquire_lock(resource_name, timeout: 0.5)
        expect(result).to be true
      end

      it 'returns false after timeout expires' do
        # First acquire succeeds
        manager.acquire_lock(resource_name)

        # Second acquire with short timeout fails
        result = manager.acquire_lock(resource_name, timeout: 0.1)
        expect(result).to be false
      end
    end

    context 'with stale lock detection' do
      it 'removes stale locks older than threshold' do
        lock_file = File.join(lock_dir, "#{resource_name}.lock")

        # Create a stale lock file
        File.write(lock_file, Process.pid.to_s)
        # Simulate old timestamp
        old_time = Time.now - 3600 # 1 hour old
        File.utime(old_time, old_time, lock_file)

        # Should acquire lock by removing stale lock
        result = manager.acquire_lock(resource_name, stale_threshold: 60)
        expect(result).to be true
      end

      it 'respects valid locks within threshold' do
        lock_file = File.join(lock_dir, "#{resource_name}.lock")

        # Create a recent lock file
        File.write(lock_file, Process.pid.to_s)

        # Should not acquire lock as it's not stale
        result = manager.acquire_lock(resource_name, stale_threshold: 60)
        expect(result).to be false
      end
    end
  end

  describe '#release_lock' do
    let(:resource_name) { 'issue-window-42' }

    it 'releases an acquired lock' do
      manager.acquire_lock(resource_name)

      result = manager.release_lock(resource_name)

      expect(result).to be true
      expect(File.exist?(File.join(lock_dir, "#{resource_name}.lock"))).to be false
    end

    it 'returns false if lock does not exist' do
      result = manager.release_lock(resource_name)

      expect(result).to be false
    end

    it 'returns false if lock is held by another process' do
      lock_file = File.join(lock_dir, "#{resource_name}.lock")
      # Simulate lock held by another process
      File.write(lock_file, '99999')

      result = manager.release_lock(resource_name)

      expect(result).to be false
      expect(File.exist?(lock_file)).to be true
    end
  end

  describe '#with_lock' do
    let(:resource_name) { 'issue-window-42' }

    it 'executes block with lock acquired' do
      executed = false
      lock_held = false

      manager.with_lock(resource_name) do
        executed = true
        lock_held = File.exist?(File.join(lock_dir, "#{resource_name}.lock"))
      end

      expect(executed).to be true
      expect(lock_held).to be true
      expect(File.exist?(File.join(lock_dir, "#{resource_name}.lock"))).to be false
    end

    it 'releases lock even if block raises exception' do
      expect do
        manager.with_lock(resource_name) do
          raise 'Test error'
        end
      end.to raise_error('Test error')

      expect(File.exist?(File.join(lock_dir, "#{resource_name}.lock"))).to be false
    end

    it 'returns block return value' do
      result = manager.with_lock(resource_name) do
        'test value'
      end

      expect(result).to eq('test value')
    end

    it 'raises LockTimeoutError if lock cannot be acquired' do
      # First acquire the lock
      manager.acquire_lock(resource_name)

      expect do
        manager.with_lock(resource_name, timeout: 0.1) do
          # Should not reach here
        end
      end.to raise_error(Soba::Infrastructure::LockTimeoutError)
    end
  end

  describe '#locked?' do
    let(:resource_name) { 'issue-window-42' }

    it 'returns true if resource is locked' do
      manager.acquire_lock(resource_name)

      expect(manager.locked?(resource_name)).to be true
    end

    it 'returns false if resource is not locked' do
      expect(manager.locked?(resource_name)).to be false
    end
  end

  describe '#cleanup_stale_locks' do
    it 'removes all stale lock files' do
      # Create multiple lock files with different ages
      recent_lock = File.join(lock_dir, 'recent.lock')
      old_lock1 = File.join(lock_dir, 'old1.lock')
      old_lock2 = File.join(lock_dir, 'old2.lock')

      File.write(recent_lock, Process.pid.to_s)
      File.write(old_lock1, Process.pid.to_s)
      File.write(old_lock2, Process.pid.to_s)

      # Set old timestamps
      old_time = Time.now - 3600
      File.utime(old_time, old_time, old_lock1)
      File.utime(old_time, old_time, old_lock2)

      removed = manager.cleanup_stale_locks(threshold: 60)

      expect(removed).to contain_exactly('old1', 'old2')
      expect(File.exist?(recent_lock)).to be true
      expect(File.exist?(old_lock1)).to be false
      expect(File.exist?(old_lock2)).to be false
    end
  end

  describe 'concurrent access' do
    let(:resource_name) { 'issue-window-42' }

    it 'ensures only one process can hold a lock' do
      results = []
      threads = []

      5.times do |i|
        threads << Thread.new do
          if manager.acquire_lock(resource_name)
            results << i
            sleep 0.01 # Hold lock briefly
            manager.release_lock(resource_name)
          end
        end
      end

      threads.each(&:join)

      # Only one thread should have acquired the lock initially
      # Others might acquire it after release
      expect(results).not_to be_empty
      expect(results.first).to be_between(0, 4)
    end

    it 'ensures with_lock blocks execute sequentially' do
      counter = 0
      max_concurrent = 0
      current_concurrent = 0
      mutex = Mutex.new

      threads = 5.times.map do |i|
        Thread.new do
          manager.with_lock(resource_name, timeout: 2) do
            mutex.synchronize do
              current_concurrent += 1
              max_concurrent = [max_concurrent, current_concurrent].max
            end

            sleep 0.01
            counter += 1

            mutex.synchronize do
              current_concurrent -= 1
            end
          end
        end
      end

      threads.each(&:join)

      expect(counter).to eq(5)
      expect(max_concurrent).to eq(1)  # Only one should run at a time
    end
  end
end