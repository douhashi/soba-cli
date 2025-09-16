# frozen_string_literal: true

require 'spec_helper'
require 'soba/infrastructure/tmux_client'

RSpec.describe Soba::Infrastructure::TmuxClient do
  let(:client) { described_class.new }

  describe '#create_session' do
    context 'when creating a new session' do
      let(:session_name) { 'soba-test-session' }

      it 'creates a tmux session with the given name' do
        allow(Open3).to receive(:capture3).with('tmux', 'new-session', '-d', '-s', session_name).
          and_return(['', '', double(exitstatus: 0)])

        result = client.create_session(session_name)

        expect(result).to be true
        expect(Open3).to have_received(:capture3).with('tmux', 'new-session', '-d', '-s', session_name)
      end

      context 'when session already exists' do
        it 'returns false' do
          allow(Open3).to receive(:capture3).with('tmux', 'new-session', '-d', '-s', session_name).
            and_return(['', 'duplicate session: soba-test-session', double(exitstatus: 1)])

          result = client.create_session(session_name)

          expect(result).to be false
        end
      end

      context 'when tmux is not available' do
        it 'raises an error' do
          allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

          expect { client.create_session(session_name) }.to raise_error(Soba::Infrastructure::TmuxError, /tmux is not installed/)
        end
      end
    end
  end

  describe '#kill_session' do
    context 'when killing an existing session' do
      let(:session_name) { 'soba-test-session' }

      it 'kills the tmux session' do
        allow(Open3).to receive(:capture3).with('tmux', 'kill-session', '-t', session_name).
          and_return(['', '', double(exitstatus: 0)])

        result = client.kill_session(session_name)

        expect(result).to be true
        expect(Open3).to have_received(:capture3).with('tmux', 'kill-session', '-t', session_name)
      end

      context 'when session does not exist' do
        it 'returns false' do
          allow(Open3).to receive(:capture3).with('tmux', 'kill-session', '-t', session_name).
            and_return(['', "can't find session", double(exitstatus: 1)])

          result = client.kill_session(session_name)

          expect(result).to be false
        end
      end
    end
  end

  describe '#session_exists?' do
    context 'when checking session existence' do
      let(:session_name) { 'soba-test-session' }

      it 'returns true for existing session' do
        allow(Open3).to receive(:capture3).with('tmux', 'has-session', '-t', session_name).
          and_return(['', '', double(exitstatus: 0)])

        result = client.session_exists?(session_name)

        expect(result).to be true
      end

      it 'returns false for non-existing session' do
        allow(Open3).to receive(:capture3).with('tmux', 'has-session', '-t', session_name).
          and_return(['', '', double(exitstatus: 1)])

        result = client.session_exists?(session_name)

        expect(result).to be false
      end
    end
  end

  describe '#list_sessions' do
    it 'returns list of active tmux sessions' do
      session_list = "soba-claude-1-1234: 1 windows\nsoba-claude-2-5678: 2 windows"
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions').
        and_return([session_list, '', double(exitstatus: 0)])

      result = client.list_sessions

      expect(result).to eq(['soba-claude-1-1234', 'soba-claude-2-5678'])
    end

    it 'returns empty array when no sessions exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions').
        and_return(['', 'no server running', double(exitstatus: 1)])

      result = client.list_sessions

      expect(result).to eq([])
    end
  end

  describe '#send_keys' do
    let(:session_name) { 'soba-test-session' }
    let(:command) { 'echo "Hello World"' }

    it 'sends keys to the tmux session' do
      allow(Open3).to receive(:capture3).with('tmux', 'send-keys', '-t', session_name, command, 'Enter').
        and_return(['', '', double(exitstatus: 0)])

      result = client.send_keys(session_name, command)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'send-keys', '-t', session_name, command, 'Enter')
    end

    it 'returns false when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'send-keys', '-t', session_name, command, 'Enter').
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.send_keys(session_name, command)

      expect(result).to be false
    end
  end

  describe '#capture_pane' do
    let(:session_name) { 'soba-test-session' }

    it 'captures the content of the tmux pane' do
      pane_content = "$ echo 'Hello World'\nHello World\n$ "
      allow(Open3).to receive(:capture3).with('tmux', 'capture-pane', '-t', session_name, '-p').
        and_return([pane_content, '', double(exitstatus: 0)])

      result = client.capture_pane(session_name)

      expect(result).to eq(pane_content)
    end

    it 'returns nil when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'capture-pane', '-t', session_name, '-p').
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.capture_pane(session_name)

      expect(result).to be_nil
    end
  end
end