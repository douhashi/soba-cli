# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require 'json'
require_relative '../../lib/soba/commands/status'
require_relative '../../lib/soba/services/pid_manager'

RSpec.describe Soba::Commands::Status do
  let(:temp_dir) { Dir.mktmpdir }
  let(:pid_file) { File.join(temp_dir, 'soba.pid') }
  let(:log_file) { File.join(temp_dir, 'daemon.log') }
  let(:status_file) { File.join(temp_dir, 'status.json') }
  let(:status_command) { described_class.new }

  before do
    allow(File).to receive(:expand_path).with('~/.soba/soba.pid').and_return(pid_file)
    allow(File).to receive(:expand_path).with('~/.soba/logs/daemon.log').and_return(log_file)
    allow(File).to receive(:expand_path).with('~/.soba/status.json').and_return(status_file)
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

    context 'with --log option' do
      context 'when specifying custom log lines' do
        before do
          File.write(pid_file, Process.pid.to_s)
          FileUtils.mkdir_p(File.dirname(log_file))
          File.open(log_file, 'w') do |f|
            20.times do |i|
              f.puts "[2024-01-01 10:00:#{i.to_s.rjust(2, '0')}] Log line #{i + 1}"
            end
          end
        end

        it 'displays the specified number of log lines' do
          output = capture_stdout { status_command.execute({}, { log: 5 }, []) }
          expect(output.scan(/Log line \d+/).size).to eq(5)
          expect(output).to include("Log line 16")
          expect(output).to include("Log line 20")
          expect(output).not_to include("Log line 15")
        end

        it 'defaults to 10 lines when log option is not provided' do
          output = capture_stdout { status_command.execute }
          expect(output.scan(/Log line \d+/).size).to eq(10)
        end
      end
    end

    context 'with --json option' do
      before do
        File.write(pid_file, Process.pid.to_s)
        FileUtils.mkdir_p(File.dirname(log_file))
        File.open(log_file, 'w') do |f|
          f.puts "[2024-01-01 10:00:00] Line 1"
          f.puts "[2024-01-01 10:00:01] Line 2"
        end
      end

      it 'outputs daemon status in JSON format' do
        output = capture_stdout { status_command.execute({}, { json: true }, []) }
        json_output = JSON.parse(output)

        expect(json_output['daemon']).to include(
          'status' => 'running',
          'pid' => Process.pid
        )
        expect(json_output['daemon']).to have_key('started_at')
        expect(json_output['daemon']).to have_key('uptime_seconds')
        expect(json_output['logs']).to be_an(Array)
        expect(json_output['logs']).to include("[2024-01-01 10:00:00] Line 1")
      end

      context 'when daemon is not running' do
        before do
          FileUtils.rm_f(pid_file)
        end

        it 'outputs not running status in JSON format' do
          output = capture_stdout { status_command.execute({}, { json: true }, []) }
          json_output = JSON.parse(output)

          expect(json_output['daemon']['status']).to eq('not_running')
          expect(json_output['daemon']).not_to have_key('pid')
        end
      end
    end

    context 'with daemon status file' do
      before do
        File.write(pid_file, Process.pid.to_s)
        FileUtils.mkdir_p(File.dirname(log_file))
        FileUtils.touch(log_file)

        # Create status file with current Issue info
        status_info = {
          current_issue: {
            number: 92,
            phase: 'soba:doing',
            started_at: '2024-01-15T10:00:00Z',
          },
          last_processed: {
            number: 91,
            completed_at: '2024-01-15T09:30:00Z',
          },
          memory_mb: 45.2,
        }
        File.write(status_file, JSON.pretty_generate(status_info))
      end

      it 'displays current Issue information' do
        output = capture_stdout { status_command.execute }
        expect(output).to include("Current Issue: #92 (soba:doing)")
      end

      it 'displays last processed Issue information' do
        output = capture_stdout { status_command.execute }
        expect(output).to include("Last Processed: #91")
      end

      it 'displays memory usage' do
        output = capture_stdout { status_command.execute }
        # Memory usage comes from the actual process, not the status file
        expect(output).to match(/Memory Usage: \d+\.\d+ MB/)
      end

      it 'includes Issue info in JSON output' do
        output = capture_stdout { status_command.execute({}, { json: true }, []) }
        json_output = JSON.parse(output)

        expect(json_output['current_issue']).to eq({
          'number' => 92,
          'phase' => 'soba:doing',
          'started_at' => '2024-01-15T10:00:00Z',
        })
        expect(json_output['last_processed']).to eq({
          'number' => 91,
          'completed_at' => '2024-01-15T09:30:00Z',
        })
        # Memory usage comes from the actual process, not the status file
        expect(json_output['daemon']['memory_mb']).to be_a(Float)
        expect(json_output['daemon']['memory_mb']).to be > 0
      end
    end

    context 'when status file is corrupted' do
      before do
        File.write(pid_file, Process.pid.to_s)
        FileUtils.mkdir_p(File.dirname(log_file))
        FileUtils.touch(log_file)
        File.write(status_file, "invalid json")
      end

      it 'handles corrupted status file gracefully' do
        output = capture_stdout { status_command.execute }
        expect(output).to match(/Daemon Status: Running/)
        # Should not crash and should continue to display basic info
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