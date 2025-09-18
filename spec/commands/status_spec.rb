# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require_relative '../../lib/soba/commands/status'
require_relative '../../lib/soba/services/pid_manager'

RSpec.describe Soba::Commands::Status do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'soba.pid') }
  let(:log_file) { File.join(temp_dir, 'daemon.log') }
  let(:status_command) { described_class.new }

  before do
    allow(File).to receive(:expand_path).with('~/.soba/soba.pid').and_return(pid_file)
    allow(File).to receive(:expand_path).with('~/.soba/logs/daemon.log').and_return(log_file)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#execute' do
    context 'when no daemon is running' do
      it 'displays that no daemon is running' do
        expect { status_command.execute }.to output(/No daemon process is running/).to_stdout
      end

      it 'returns 0' do
        expect(status_command.execute).to eq(0)
      end
    end

    context 'when daemon is running' do
      before do
        # Create PID file with current process
        File.write(pid_file, Process.pid.to_s)
        # Create log file with some content
        FileUtils.mkdir_p(File.dirname(log_file))
        File.open(log_file, 'w') do |f|
          f.puts "[2024-01-01 10:00:00] Daemon started successfully (PID: #{Process.pid})"
          f.puts "[2024-01-01 10:00:01] Starting workflow monitor for test/repo"
          f.puts "[2024-01-01 10:00:02] Polling interval: 10 seconds"
        end
      end

      it 'displays daemon status' do
        output = capture_stdout { status_command.execute }
        expect(output).to match(/Daemon Status: Running/)
        expect(output).to match(/PID: #{Process.pid}/)
      end

      it 'displays recent logs' do
        output = capture_stdout { status_command.execute }
        expect(output).to include("Daemon started successfully")
        expect(output).to include("Starting workflow monitor")
      end

      it 'returns 0' do
        expect(status_command.execute).to eq(0)
      end
    end

    context 'when PID file exists but process is dead' do
      before do
        # Create PID file with non-existent process
        File.write(pid_file, '999999')
      end

      it 'displays that daemon is not running' do
        output = capture_stdout { status_command.execute }
        expect(output).to match(/Daemon Status: Not running/)
        expect(output).to match(/Stale PID file found/)
      end

      it 'returns 1' do
        expect(status_command.execute).to eq(1)
      end
    end

    context 'when log file does not exist' do
      before do
        File.write(pid_file, Process.pid.to_s)
      end

      it 'handles missing log file gracefully' do
        output = capture_stdout { status_command.execute }
        expect(output).to match(/Daemon Status: Running/)
        expect(output).to match(/No log file found/)
      end
    end

    context 'when log file is empty' do
      before do
        File.write(pid_file, Process.pid.to_s)
        FileUtils.mkdir_p(File.dirname(log_file))
        FileUtils.touch(log_file)
      end

      it 'handles empty log file gracefully' do
        output = capture_stdout { status_command.execute }
        expect(output).to match(/Daemon Status: Running/)
        expect(output).to match(/Log file is empty/)
      end
    end
  end

  private

  def capture_stdout(&block)
    old_stdout = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end