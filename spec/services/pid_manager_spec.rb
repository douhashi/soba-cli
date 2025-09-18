# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tempfile'
require_relative '../../lib/soba/services/pid_manager'

RSpec.describe Soba::Services::PidManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'test.pid') }
  let(:pid_manager) { described_class.new(pid_file) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#write' do
    it 'writes the current process PID to the file' do
      pid_manager.write
      expect(File.exist?(pid_file)).to be true
      expect(File.read(pid_file).strip.to_i).to eq(Process.pid)
    end

    it 'creates the directory if it does not exist' do
      deep_path = File.join(temp_dir, 'nested', 'dir', 'test.pid')
      manager = described_class.new(deep_path)
      manager.write
      expect(File.exist?(deep_path)).to be true
    end

    it 'overwrites existing PID file' do
      File.write(pid_file, '12345')
      pid_manager.write
      expect(File.read(pid_file).strip.to_i).to eq(Process.pid)
    end
  end

  describe '#read' do
    context 'when PID file exists' do
      it 'returns the PID as an integer' do
        File.write(pid_file, '12345')
        expect(pid_manager.read).to eq(12345)
      end

      it 'handles whitespace in PID file' do
        File.write(pid_file, "  12345\n  ")
        expect(pid_manager.read).to eq(12345)
      end
    end

    context 'when PID file does not exist' do
      it 'returns nil' do
        expect(pid_manager.read).to be_nil
      end
    end
  end

  describe '#delete' do
    context 'when PID file exists' do
      before do
        File.write(pid_file, '12345')
      end

      it 'deletes the PID file' do
        expect(pid_manager.delete).to be true
        expect(File.exist?(pid_file)).to be false
      end
    end

    context 'when PID file does not exist' do
      it 'returns false' do
        expect(pid_manager.delete).to be false
      end
    end
  end

  describe '#running?' do
    context 'when PID file does not exist' do
      it 'returns false' do
        expect(pid_manager.running?).to be false
      end
    end

    context 'when PID file exists' do
      context 'when process is running' do
        it 'returns true' do
          pid_manager.write
          expect(pid_manager.running?).to be true
        end
      end

      context 'when process is not running' do
        it 'returns false' do
          # Use a PID that is unlikely to exist
          File.write(pid_file, '999999')
          expect(pid_manager.running?).to be false
        end
      end

      context 'when PID is invalid' do
        it 'returns false' do
          File.write(pid_file, 'invalid')
          expect(pid_manager.running?).to be false
        end
      end
    end
  end

  describe '#cleanup_if_stale' do
    context 'when PID file does not exist' do
      it 'returns false' do
        expect(pid_manager.cleanup_if_stale).to be false
      end
    end

    context 'when process is running' do
      it 'does not delete the PID file and returns false' do
        pid_manager.write
        expect(pid_manager.cleanup_if_stale).to be false
        expect(File.exist?(pid_file)).to be true
      end
    end

    context 'when process is not running' do
      before do
        File.write(pid_file, '999999')
      end

      it 'deletes the stale PID file and returns true' do
        expect(pid_manager.cleanup_if_stale).to be true
        expect(File.exist?(pid_file)).to be false
      end
    end
  end

  describe '#lock' do
    it 'acquires an exclusive lock on the PID file' do
      pid_manager.write

      locked = false
      pid_manager.lock do
        # Try to acquire lock from another instance
        another_manager = described_class.new(pid_file)
        thread = Thread.new do
          another_manager.lock(timeout: 0.1) do
            locked = true
          end
        rescue Timeout::Error
          # Expected behavior
        end
        thread.join

        expect(locked).to be false
      end
    end

    it 'yields to the block when lock is acquired' do
      executed = false
      pid_manager.lock do
        executed = true
      end
      expect(executed).to be true
    end

    it 'raises Timeout::Error when lock cannot be acquired' do
      pid_manager.write

      # First lock
      thread = Thread.new do
        pid_manager.lock do
          sleep 0.5
        end
      end

      sleep 0.1 # Ensure first lock is acquired

      # Try to acquire second lock
      another_manager = described_class.new(pid_file)
      expect do
        another_manager.lock(timeout: 0.1) {}
      end.to raise_error(Timeout::Error)

      thread.join
    end
  end
end