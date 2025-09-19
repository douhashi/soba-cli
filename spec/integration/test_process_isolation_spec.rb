# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/tmux_session_manager'
require 'soba/services/test_process_manager'

RSpec.describe 'Test Process Isolation', type: :integration, test_process_isolation: true do
  let(:mock_tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:tmux_session_manager) { Soba::Services::TmuxSessionManager.new(tmux_client: mock_tmux_client) }
  let(:test_process_manager) { Soba::Services::TestProcessManager.new }
  let(:repository) { 'test/repo' }

  describe 'session name generation in test mode' do
    it 'generates test-specific session names' do
      expect(in_test_mode?).to be true

      session_name = tmux_session_manager.send(:generate_session_name, repository)

      expect(session_name).to start_with('soba-test-test-repo-')
      expect(session_name).to include(Process.pid.to_s)
      expect(session_name).to match(/soba-test-test-repo-\d+-[a-f0-9]{8}/)
    end

    it 'generates unique session names for parallel tests' do
      session_name_1 = tmux_session_manager.send(:generate_session_name, repository)
      session_name_2 = tmux_session_manager.send(:generate_session_name, repository)

      expect(session_name_1).not_to eq(session_name_2)
    end
  end

  describe 'test environment isolation' do
    it 'ensures test environment is properly setup' do
      result = test_process_manager.ensure_test_environment

      expect(result[:success]).to be true
      expect(result[:test_mode]).to be true
      expect(Dir.exist?('/tmp/soba-test-pids')).to be true
    end

    it 'provides unique test IDs for each test' do
      test_id_1 = test_process_manager.generate_test_id
      test_id_2 = test_process_manager.generate_test_id

      expect(test_id_1).not_to eq(test_id_2)
      expect(test_id_1).to match(/\d+-[a-f0-9]{8}/)
      expect(test_id_2).to match(/\d+-[a-f0-9]{8}/)
    end
  end

  describe 'PID file management' do
    let(:test_id) { test_process_manager.generate_test_id }

    it 'creates test-specific PID files' do
      pid_manager = test_process_manager.create_test_pid_manager(test_id)

      expect(pid_manager.pid_file).to eq("/tmp/soba-test-pids/#{test_id}.pid")
    end

    it 'writes and reads PID files correctly' do
      pid_manager = test_process_manager.create_test_pid_manager(test_id)
      test_pid = 12345

      pid_manager.write(test_pid)
      expect(pid_manager.read).to eq(test_pid)

      pid_manager.delete
      expect(pid_manager.read).to be_nil
    end
  end

  describe 'process cleanup' do
    let(:test_id) { test_process_manager.generate_test_id }

    context 'when no processes exist' do
      it 'returns success without errors' do
        result = test_process_manager.cleanup_test_processes(test_id)

        expect(result[:success]).to be true
        expect(result[:cleaned_processes]).to eq([])
      end
    end

    context 'when PID file exists but process is not running' do
      it 'cleans up stale PID file' do
        pid_manager = test_process_manager.create_test_pid_manager(test_id)
        non_existent_pid = 999999

        pid_manager.write(non_existent_pid)
        expect(File.exist?(pid_manager.pid_file)).to be true

        result = test_process_manager.cleanup_test_processes(test_id)

        expect(result[:success]).to be true
        expect(result[:cleaned_processes]).to eq([])
        expect(File.exist?(pid_manager.pid_file)).to be false
      end
    end
  end

  describe 'test helper integration' do
    it 'provides current test ID through helper method' do
      expect(current_test_id).to be_present
      expect(current_test_id).to match(/\d+-[a-f0-9]{8}/)
    end

    it 'provides test process manager through helper method' do
      expect(test_process_manager).to be_a(Soba::Services::TestProcessManager)
      expect(test_process_manager.test_mode?).to be true
    end

    it 'confirms test mode is active' do
      expect(in_test_mode?).to be true
    end
  end

  describe 'parallel test execution simulation' do
    it 'ensures each test gets isolated resources' do
      # Simulate multiple tests running in parallel
      test_contexts = 3.times.map do
        {
          test_id: test_process_manager.generate_test_id,
          session_name: tmux_session_manager.send(:generate_session_name, repository),
        }
      end

      # All test IDs should be unique
      test_ids = test_contexts.map { |ctx| ctx[:test_id] }
      expect(test_ids.uniq.size).to eq(3)

      # All session names should be unique
      session_names = test_contexts.map { |ctx| ctx[:session_name] }
      expect(session_names.uniq.size).to eq(3)

      # All should follow the test naming pattern
      session_names.each do |name|
        expect(name).to start_with('soba-test-test-repo-')
      end
    end
  end
end