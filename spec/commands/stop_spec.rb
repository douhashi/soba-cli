# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require_relative '../../lib/soba/commands/stop'
require_relative '../../lib/soba/services/pid_manager'
require_relative '../../lib/soba/infrastructure/tmux_client'

RSpec.describe Soba::Commands::Stop do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'soba.pid') }
  let(:stop_command) { described_class.new }

  before do
    ENV['SOBA_TEST_PID_FILE'] = pid_file
  end

  after do
    ENV.delete('SOBA_TEST_PID_FILE')
    FileUtils.rm_rf(temp_dir)
  end

  describe '#execute' do
    context 'when no daemon is running' do
      it 'displays that no daemon is running' do
        expect { stop_command.execute }.to output(/No daemon process is running/).to_stdout
      end

      it 'returns 1' do
        expect(stop_command.execute).to eq(1)
      end
    end

    context 'with --force option' do
      let(:test_pid) { Process.pid }
      let(:options) { { force: true } }

      before do
        File.write(pid_file, test_pid.to_s)
        allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
        allow(Process).to receive(:kill).with('KILL', test_pid).and_return(1)
        allow(stop_command).to receive(:cleanup_tmux_sessions) # Prevent actual tmux operations
      end

      it 'immediately sends SIGKILL without waiting' do
        expect(Process).to receive(:kill).with('KILL', test_pid)
        expect(stop_command).not_to receive(:wait_for_termination)
        stop_command.execute({}, options)
      end

      it 'displays force kill message' do
        expect { stop_command.execute({}, options) }.to output(/Forcefully terminating daemon/).to_stdout
      end

      it 'removes the PID file' do
        stop_command.execute({}, options)
        expect(File.exist?(pid_file)).to be false
      end

      it 'returns 0 on success' do
        expect(stop_command.execute({}, options)).to eq(0)
      end
    end

    context 'with --timeout option' do
      let(:test_pid) { Process.pid }
      let(:options) { { timeout: 5 } }

      before do
        File.write(pid_file, test_pid.to_s)
        allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
        allow(Process).to receive(:kill).with('TERM', test_pid).and_return(1)
        allow(Process).to receive(:kill).with('KILL', test_pid).and_return(1)
        allow(stop_command).to receive(:cleanup_tmux_sessions) # Prevent actual tmux operations
      end

      it 'uses custom timeout value' do
        expect(stop_command).to receive(:wait_for_termination).with(test_pid, timeout: 5).and_return(false)
        stop_command.execute({}, options)
      end
    end

    context 'when daemon is running' do
      let(:test_pid) { Process.pid }

      before do
        # Create PID file with current process
        File.write(pid_file, test_pid.to_s)
        # Mock Process.kill to prevent actually killing the test process
        allow(stop_command).to receive(:cleanup_tmux_sessions) # Prevent actual tmux operations
        # First check if running (kill 0), then send TERM
        call_count = 0
        allow(Process).to receive(:kill) do |signal, pid|
          if pid == test_pid
            call_count += 1
            case [signal, call_count]
            when [0, 1]
              1  # Process is running
            when ['TERM', 2]
              1  # SIGTERM sent
            when [0, 3], [0, 4], [0, 5]
              raise Errno::ESRCH # Process terminated
            else
              raise "Unexpected kill call: #{signal} #{call_count}"
            end
          end
        end
      end

      it 'sends SIGTERM to the process' do
        expect(Process).to receive(:kill).with('TERM', test_pid)
        stop_command.execute
      end

      it 'waits for process to terminate' do
        expect(stop_command).to receive(:wait_for_termination).with(test_pid, timeout: 30)
        stop_command.execute
      end

      it 'removes the PID file' do
        allow(stop_command).to receive(:wait_for_termination).and_return(true)
        stop_command.execute
        expect(File.exist?(pid_file)).to be false
      end

      it 'displays success message' do
        allow(stop_command).to receive(:wait_for_termination).and_return(true)
        expect { stop_command.execute }.to output(/Daemon stopped successfully/).to_stdout
      end

      it 'returns 0 on success' do
        allow(stop_command).to receive(:wait_for_termination).and_return(true)
        expect(stop_command.execute).to eq(0)
      end
    end

    context 'when PID file exists but process is already dead' do
      before do
        # Create PID file with non-existent process
        File.write(pid_file, '999999')
      end

      it 'cleans up stale PID file' do
        stop_command.execute
        expect(File.exist?(pid_file)).to be false
      end

      it 'displays appropriate message' do
        expect { stop_command.execute }.to output(/Daemon was not running.*cleaned up/).to_stdout
      end

      it 'returns 0' do
        expect(stop_command.execute).to eq(0)
      end
    end

    context 'when process does not terminate gracefully' do
      let(:test_pid) { Process.pid }

      before do
        File.write(pid_file, test_pid.to_s)
        allow(Process).to receive(:kill).with('TERM', test_pid).and_return(1)
        allow(Process).to receive(:kill).with('KILL', test_pid).and_return(1)
        allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
        allow(stop_command).to receive(:cleanup_tmux_sessions) # Prevent actual tmux operations
      end

      it 'forcefully kills the process after timeout' do
        allow(stop_command).to receive(:wait_for_termination).and_return(false)
        expect(Process).to receive(:kill).with('KILL', test_pid)
        stop_command.execute
      end

      it 'displays force kill message' do
        allow(stop_command).to receive(:wait_for_termination).and_return(false)
        allow(Process).to receive(:kill).with('KILL', test_pid)
        expect { stop_command.execute }.to output(/forcefully terminating/).to_stdout
      end
    end

    context 'when unable to kill process' do
      let(:test_pid) { 1 } # Usually init process, can't be killed

      before do
        File.write(pid_file, test_pid.to_s)
        allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
        allow(Process).to receive(:kill).with('TERM', test_pid).and_raise(Errno::EPERM)
        allow(stop_command).to receive(:cleanup_tmux_sessions) # Prevent actual tmux operations
      end

      it 'displays permission error' do
        expect { stop_command.execute }.to output(/Permission denied/).to_stdout
      end

      it 'returns 1' do
        expect(stop_command.execute).to eq(1)
      end
    end
  end

  describe '#wait_for_termination' do
    let(:test_pid) { 12345 }

    context 'when process terminates quickly' do
      it 'returns true' do
        allow(Process).to receive(:kill).with(0, test_pid).and_raise(Errno::ESRCH)
        expect(stop_command.send(:wait_for_termination, test_pid, timeout: 1)).to be true
      end
    end

    context 'when process does not terminate' do
      it 'returns false after timeout' do
        allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
        expect(stop_command.send(:wait_for_termination, test_pid, timeout: 0.1)).to be false
      end
    end
  end

  describe 'graceful shutdown' do
    let(:test_pid) { Process.pid }
    let(:stopping_file) { '/tmp/test_stopping' }

    before do
      File.write(pid_file, test_pid.to_s)
      allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
      allow(Process).to receive(:kill).with('TERM', test_pid).and_return(1)
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.soba/stopping').and_return(stopping_file)
      allow(FileUtils).to receive(:touch)
      allow(FileUtils).to receive(:rm_f)
    end

    after do
      FileUtils.rm_f(stopping_file) if File.exist?(stopping_file)
    end

    it 'creates a stopping file for graceful shutdown' do
      allow(stop_command).to receive(:wait_for_termination).and_return(true)
      expect(FileUtils).to receive(:touch).with(stopping_file)
      stop_command.execute
    end

    it 'removes the stopping file after successful stop' do
      allow(stop_command).to receive(:wait_for_termination).and_return(true)
      expect(FileUtils).to receive(:rm_f).with(stopping_file)
      stop_command.execute
    end

    it 'removes the stopping file even after force kill' do
      allow(stop_command).to receive(:wait_for_termination).and_return(false)
      allow(Process).to receive(:kill).with('KILL', test_pid).and_return(1)
      expect(FileUtils).to receive(:rm_f).with(stopping_file)
      stop_command.execute
    end
  end

  describe 'tmux session cleanup' do
    let(:test_pid) { Process.pid }
    let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }

    before do
      File.write(pid_file, test_pid.to_s)
      allow(Process).to receive(:kill).with(0, test_pid).and_return(1)
      allow(Process).to receive(:kill).with('TERM', test_pid).and_return(1)
      allow(stop_command).to receive(:wait_for_termination).and_return(true)
      allow(stop_command).to receive(:cleanup_tmux_sessions) # Mock cleanup to prevent actual tmux operations
      allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
    end

    context 'when tmux sessions exist' do
      before do
        allow(tmux_client).to receive(:list_soba_sessions).and_return(['soba-issue-123', 'soba-issue-456'])
        allow(tmux_client).to receive(:kill_session).and_return(true)
        allow(stop_command).to receive(:cleanup_tmux_sessions).and_call_original
      end

      it 'kills all soba tmux sessions' do
        expect(tmux_client).to receive(:kill_session).with('soba-issue-123')
        expect(tmux_client).to receive(:kill_session).with('soba-issue-456')
        stop_command.execute
      end

      it 'displays cleanup message' do
        expect { stop_command.execute }.to output(/Cleaning up tmux sessions/).to_stdout
      end
    end

    context 'when no tmux sessions exist' do
      before do
        allow(tmux_client).to receive(:list_soba_sessions).and_return([])
        allow(stop_command).to receive(:cleanup_tmux_sessions).and_call_original
      end

      it 'does not attempt to kill any sessions' do
        expect(tmux_client).not_to receive(:kill_session)
        stop_command.execute
      end
    end

    context 'when tmux session cleanup fails' do
      before do
        allow(tmux_client).to receive(:list_soba_sessions).and_return(['soba-issue-123'])
        allow(tmux_client).to receive(:kill_session).and_return(false)
        allow(stop_command).to receive(:cleanup_tmux_sessions).and_call_original
      end

      it 'continues with daemon stop even if tmux cleanup fails' do
        result = nil
        expect { result = stop_command.execute }.to output(/Warning: Failed to kill tmux session/).to_stdout
        expect(result).to eq(0)
      end
    end
  end
end