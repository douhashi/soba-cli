# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/test_process_manager'

RSpec.describe Soba::Services::TestProcessManager, test_process_isolation: true do
  subject(:manager) { described_class.new }

  describe '#test_mode?' do
    context 'when SOBA_TEST_MODE is set to true' do
      before { allow(ENV).to receive(:[]).with('SOBA_TEST_MODE').and_return('true') }

      it 'returns true' do
        expect(manager.test_mode?).to be true
      end
    end

    context 'when SOBA_TEST_MODE is not set' do
      before { allow(ENV).to receive(:[]).with('SOBA_TEST_MODE').and_return(nil) }

      it 'returns false' do
        expect(manager.test_mode?).to be false
      end
    end

    context 'when SOBA_TEST_MODE is set to false' do
      before { allow(ENV).to receive(:[]).with('SOBA_TEST_MODE').and_return('false') }

      it 'returns false' do
        expect(manager.test_mode?).to be false
      end
    end
  end

  describe '#generate_test_session_name' do
    let(:repository) { 'owner/repo' }

    before do
      allow(Process).to receive(:pid).and_return(12345)
      allow(SecureRandom).to receive(:hex).with(4).and_return('abcd1234')
    end

    it 'generates a test session name with PID and random hex' do
      expected_name = 'soba-test-owner-repo-12345-abcd1234'
      expect(manager.generate_test_session_name(repository)).to eq(expected_name)
    end

    it 'sanitizes repository name' do
      repo_with_special_chars = 'owner/repo.name_with-chars'
      expected_name = 'soba-test-owner-repo-name-with-chars-12345-abcd1234'
      expect(manager.generate_test_session_name(repo_with_special_chars)).to eq(expected_name)
    end
  end

  describe '#generate_test_id' do
    before do
      allow(Process).to receive(:pid).and_return(12345)
      allow(SecureRandom).to receive(:hex).with(4).and_return('abcd1234')
    end

    it 'generates a unique test identifier' do
      expected_id = '12345-abcd1234'
      expect(manager.generate_test_id).to eq(expected_id)
    end
  end

  describe '#test_pid_file_path' do
    let(:test_id) { '12345-abcd1234' }

    it 'returns the test PID file path' do
      expected_path = "/tmp/soba-test-pids/#{test_id}.pid"
      expect(manager.test_pid_file_path(test_id)).to eq(expected_path)
    end
  end

  describe '#create_test_pid_manager' do
    let(:test_id) { '12345-abcd1234' }

    it 'creates a PidManager with test-specific path' do
      pid_manager = manager.create_test_pid_manager(test_id)

      expect(pid_manager).to be_a(Soba::Services::PidManager)
      expect(pid_manager.pid_file).to eq("/tmp/soba-test-pids/#{test_id}.pid")
    end
  end

  describe '#cleanup_test_processes' do
    let(:test_id) { '12345-abcd1234' }
    let(:pid_manager) { instance_double(Soba::Services::PidManager) }

    before do
      allow(manager).to receive(:create_test_pid_manager).with(test_id).and_return(pid_manager)
    end

    context 'when PID file exists and process is running' do
      before do
        allow(pid_manager).to receive(:read).and_return(9999)
        allow(pid_manager).to receive(:running?).and_return(true)
        allow(Process).to receive(:kill).with('TERM', 9999)
        allow(Process).to receive(:kill).with('KILL', 9999)
        allow(pid_manager).to receive(:delete).and_return(true)
      end

      it 'terminates the process gracefully and cleans up PID file' do
        expect(Process).to receive(:kill).with('TERM', 9999)
        expect(Process).to receive(:kill).with('KILL', 9999)
        expect(pid_manager).to receive(:delete)

        result = manager.cleanup_test_processes(test_id)
        expect(result[:success]).to be true
        expect(result[:cleaned_processes]).to eq([9999])
      end
    end

    context 'when PID file does not exist' do
      before do
        allow(pid_manager).to receive(:read).and_return(nil)
      end

      it 'returns success without cleaning any processes' do
        result = manager.cleanup_test_processes(test_id)
        expect(result[:success]).to be true
        expect(result[:cleaned_processes]).to eq([])
      end
    end

    context 'when process is not running' do
      before do
        allow(pid_manager).to receive(:read).and_return(9999)
        allow(pid_manager).to receive(:running?).and_return(false)
        allow(pid_manager).to receive(:delete).and_return(true)
      end

      it 'cleans up stale PID file' do
        expect(pid_manager).to receive(:delete)

        result = manager.cleanup_test_processes(test_id)
        expect(result[:success]).to be true
        expect(result[:cleaned_processes]).to eq([])
      end
    end
  end

  describe '#ensure_test_environment' do
    context 'when in test mode' do
      before do
        allow(manager).to receive(:test_mode?).and_return(true)
        allow(FileUtils).to receive(:mkdir_p)
      end

      it 'creates test PID directory' do
        expect(FileUtils).to receive(:mkdir_p).with('/tmp/soba-test-pids')

        result = manager.ensure_test_environment
        expect(result[:success]).to be true
        expect(result[:test_mode]).to be true
      end
    end

    context 'when not in test mode' do
      before do
        allow(manager).to receive(:test_mode?).and_return(false)
      end

      it 'does not create test directories' do
        expect(FileUtils).not_to receive(:mkdir_p)

        result = manager.ensure_test_environment
        expect(result[:success]).to be true
        expect(result[:test_mode]).to be false
      end
    end
  end
end