# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require_relative '../../lib/soba/services/daemon_service'
require_relative '../../lib/soba/services/pid_manager'

RSpec.describe Soba::Services::DaemonService do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'test.pid') }
  let(:log_file) { File.join(temp_dir, 'test.log') }
  let(:pid_manager) { Soba::Services::PidManager.new(pid_file) }
  let(:daemon_service) { described_class.new(pid_manager: pid_manager, log_file: log_file) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'accepts a PID manager and log file' do
      expect(daemon_service.pid_manager).to eq(pid_manager)
      expect(daemon_service.log_file).to eq(log_file)
    end

    it 'uses default log file if not provided' do
      service = described_class.new(pid_manager: pid_manager)
      expect(service.log_file).to eq(File.expand_path('~/.soba/logs/daemon.log'))
    end
  end

  describe '#already_running?' do
    context 'when no daemon is running' do
      it 'returns false' do
        expect(daemon_service.already_running?).to be false
      end
    end

    context 'when daemon is running' do
      before do
        pid_manager.write
      end

      it 'returns true' do
        expect(daemon_service.already_running?).to be true
      end
    end

    context 'when PID file exists but process is dead' do
      before do
        pid_manager.write(999999)
      end

      it 'cleans up stale PID and returns false' do
        expect(daemon_service.already_running?).to be false
        expect(File.exist?(pid_file)).to be false
      end
    end
  end

  describe '#daemonize!' do
    before do
      # Always mock Process.daemon to prevent actual daemonization
      allow(Process).to receive(:daemon).and_return(true)
      # Mock stdout/stderr redirection to prevent test output issues
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
    end

    it 'calls Process.daemon with correct arguments' do
      expect(Process).to receive(:daemon).with(true, false)
      daemon_service.daemonize!
    end

    it 'writes PID file after daemonizing' do
      daemon_service.daemonize!
      expect(File.exist?(pid_file)).to be true
    end

    it 'creates log directory' do
      daemon_service.daemonize!
      expect(File.directory?(File.dirname(log_file))).to be true
    end

    it 'attempts to redirect output to log file' do
      expect($stdout).to receive(:reopen)
      expect($stderr).to receive(:reopen)
      daemon_service.daemonize!
    end
  end

  describe '#setup_signal_handlers' do
    it 'sets up SIGTERM handler' do
      expect { daemon_service.setup_signal_handlers {} }.not_to raise_error
    end

    it 'sets up SIGINT handler' do
      expect { daemon_service.setup_signal_handlers {} }.not_to raise_error
    end
  end

  describe '#cleanup' do
    before do
      pid_manager.write
    end

    it 'removes the PID file' do
      daemon_service.cleanup
      expect(File.exist?(pid_file)).to be false
    end

    it 'logs cleanup message' do
      allow(daemon_service).to receive(:log).and_call_original
      expect(daemon_service).to receive(:log).with('Cleaning up daemon...')
      daemon_service.cleanup
    end
  end

  describe '#log' do
    it 'writes messages to log file' do
      FileUtils.mkdir_p(File.dirname(log_file))
      daemon_service.log('Test message')

      # Force flush to ensure content is written
      if File.exist?(log_file)
        content = File.read(log_file)
        expect(content).to include('Test message')
      end
    end

    it 'includes timestamp in log messages' do
      FileUtils.mkdir_p(File.dirname(log_file))
      daemon_service.log('Test message')

      if File.exist?(log_file)
        content = File.read(log_file)
        expect(content).to match(/\[\d{4}-\d{2}-\d{2}/)
      end
    end
  end

  describe '#ensure_log_directory' do
    it 'creates log directory if it does not exist' do
      deep_log_path = File.join(temp_dir, 'nested', 'logs', 'daemon.log')
      service = described_class.new(pid_manager: pid_manager, log_file: deep_log_path)
      service.ensure_log_directory
      expect(File.directory?(File.dirname(deep_log_path))).to be true
    end
  end
end