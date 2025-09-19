# frozen_string_literal: true

require 'spec_helper'
require 'soba/commands/open'
require 'soba/commands/start'
require 'soba/services/pid_manager'
require 'soba/infrastructure/tmux_client'
require 'fileutils'

RSpec.describe 'Open Command Integration', integration: true do
  let(:tmux_client) { Soba::Infrastructure::TmuxClient.new }
  let(:repository) { 'test-repo' }
  let(:pid_dir) { File.join(Dir.home, '.soba', 'pids') }
  let(:pid_file) { File.join(pid_dir, "#{repository.gsub('/', '-')}.pid") }

  before do
    # Setup test environment
    FileUtils.mkdir_p(pid_dir)

    # Clean up any existing sessions
    sessions = tmux_client.list_sessions || []
    sessions.each do |session|
      if session.start_with?('soba-test')
        tmux_client.kill_session(session)
      end
    end

    # Clean up PID file
    File.delete(pid_file) if File.exist?(pid_file)

    # Mock configuration
    allow(Soba::Configuration).to receive(:load!)
    config = instance_double('Config')
    github_config = instance_double('GithubConfig')
    allow(github_config).to receive(:repository).and_return(repository)
    allow(config).to receive(:github).and_return(github_config)
    allow(Soba::Configuration).to receive(:config).and_return(config)
  end

  after do
    # Clean up test sessions
    sessions = tmux_client.list_sessions || []
    sessions.each do |session|
      if session.start_with?('soba-test')
        tmux_client.kill_session(session)
      end
    end

    # Clean up PID file
    File.delete(pid_file) if File.exist?(pid_file)
  end

  describe 'PID-based session resolution' do
    it 'finds and attaches to session created with the same PID' do
      # Skip if tmux is not available
      skip 'tmux not available' unless tmux_client.tmux_installed?

      # Create a session with a specific PID
      pid = Process.pid
      session_name = "soba-test-repo-#{pid}"

      # Create session and write PID file
      tmux_client.create_session(session_name)
      pid_manager = Soba::Services::PidManager.new(pid_file)
      pid_manager.write(pid)

      # Try to open the session using the Open command
      open_command = Soba::Commands::Open.new

      # Mock attach_to_session to prevent actual attachment
      allow(tmux_client).to receive(:attach_to_session).with(session_name)

      # Execute should find the session by PID
      expect { open_command.execute(nil) }.to output(/リポジトリのセッション #{session_name} にアタッチします/).to_stdout

      # Verify session exists
      expect(tmux_client.session_exists?(session_name)).to be true
    end

    it 'cleans up stale PID file when session does not exist' do
      # Skip if tmux is not available
      skip 'tmux not available' unless tmux_client.tmux_installed?

      # Write a PID file without creating a session
      pid = 99999 # Non-existent PID
      pid_manager = Soba::Services::PidManager.new(pid_file)
      pid_manager.write(pid)

      # Try to open the session using the Open command
      open_command = Soba::Commands::Open.new

      # Execute should not find the session and raise error
      expect { open_command.execute(nil) }.to raise_error(
        Soba::Commands::Open::SessionNotFoundError,
        /リポジトリのセッションが見つかりません/
      )

      # Verify PID file was cleaned up
      expect(File.exist?(pid_file)).to be false
    end

    it 'handles multiple processes correctly' do
      # Skip if tmux is not available
      skip 'tmux not available' unless tmux_client.tmux_installed?

      # Create multiple sessions with different PIDs
      pid1 = 12345
      pid2 = 67890
      session1 = "soba-test-repo-#{pid1}"
      session2 = "soba-test-repo-#{pid2}"

      # Create only the second session
      tmux_client.create_session(session2)

      # Write the second PID to file (simulating the most recent process)
      pid_manager = Soba::Services::PidManager.new(pid_file)
      pid_manager.write(pid2)

      # Try to open the session using the Open command
      open_command = Soba::Commands::Open.new

      # Mock attach_to_session to prevent actual attachment
      allow(tmux_client).to receive(:attach_to_session).with(session2)

      # Execute should find the correct session
      expect { open_command.execute(nil) }.to output(/リポジトリのセッション #{session2} にアタッチします/).to_stdout

      # Verify correct session exists
      expect(tmux_client.session_exists?(session2)).to be true
      expect(tmux_client.session_exists?(session1)).to be false
    end
  end

  describe 'backward compatibility' do
    it 'falls back to standard session search when no PID file exists' do
      # Skip if tmux is not available
      skip 'tmux not available' unless tmux_client.tmux_installed?

      # Create a session without PID
      session_name = "soba-test-repo-#{Process.pid}"
      tmux_client.create_session(session_name)

      # Ensure no PID file exists
      File.delete(pid_file) if File.exist?(pid_file)

      # Try to open the session using the Open command
      open_command = Soba::Commands::Open.new

      # Mock attach_to_session to prevent actual attachment
      allow(tmux_client).to receive(:attach_to_session).with(session_name)

      # Execute should find the session through standard search
      expect { open_command.execute(nil) }.to output(/リポジトリのセッション #{session_name} にアタッチします/).to_stdout

      # Verify session exists
      expect(tmux_client.session_exists?(session_name)).to be true
    end
  end
end