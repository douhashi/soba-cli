# frozen_string_literal: true

require 'spec_helper'
require 'soba/infrastructure/tmux_client'
require 'soba/infrastructure/errors'

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

          expect { client.create_session(session_name) }.to raise_error(Soba::Infrastructure::TmuxNotInstalled, /tmux is not installed/)
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

  describe '#create_window' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }

    it 'creates a new window in the session' do
      allow(Open3).to receive(:capture3).with('tmux', 'new-window', '-t', session_name, '-n', window_name).
        and_return(['', '', double(exitstatus: 0)])

      result = client.create_window(session_name, window_name)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'new-window', '-t', session_name, '-n', window_name)
    end

    it 'returns false when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'new-window', '-t', session_name, '-n', window_name).
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.create_window(session_name, window_name)

      expect(result).to be false
    end
  end

  describe '#switch_window' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }

    it 'switches to the specified window' do
      allow(Open3).to receive(:capture3).with('tmux', 'select-window', '-t', "#{session_name}:#{window_name}").
        and_return(['', '', double(exitstatus: 0)])

      result = client.switch_window(session_name, window_name)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'select-window', '-t', "#{session_name}:#{window_name}")
    end

    it 'returns false when window does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'select-window', '-t', "#{session_name}:#{window_name}").
        and_return(['', "can't find window", double(exitstatus: 1)])

      result = client.switch_window(session_name, window_name)

      expect(result).to be false
    end
  end

  describe '#list_windows' do
    let(:session_name) { 'soba-test-session' }

    it 'returns list of windows in the session' do
      windows_list = "0: bash* (1 panes) [80x24]\n1: vim (1 panes) [80x24]\n2: test-window (1 panes) [80x24]"
      allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
        and_return([windows_list, '', double(exitstatus: 0)])

      result = client.list_windows(session_name)

      expect(result).to eq(['bash', 'vim', 'test-window'])
    end

    it 'returns empty array when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.list_windows(session_name)

      expect(result).to eq([])
    end
  end

  describe '#rename_window' do
    let(:session_name) { 'soba-test-session' }
    let(:old_name) { 'old-window' }
    let(:new_name) { 'new-window' }

    it 'renames the window' do
      allow(Open3).to receive(:capture3).with('tmux', 'rename-window', '-t', "#{session_name}:#{old_name}", new_name).
        and_return(['', '', double(exitstatus: 0)])

      result = client.rename_window(session_name, old_name, new_name)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'rename-window', '-t', "#{session_name}:#{old_name}", new_name)
    end

    it 'returns false when window does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'rename-window', '-t', "#{session_name}:#{old_name}", new_name).
        and_return(['', "can't find window", double(exitstatus: 1)])

      result = client.rename_window(session_name, old_name, new_name)

      expect(result).to be false
    end
  end

  describe '#split_pane' do
    let(:session_name) { 'soba-test-session' }

    it 'splits the pane vertically' do
      allow(Open3).to receive(:capture3).with('tmux', 'split-window', '-t', session_name, '-v').
        and_return(['', '', double(exitstatus: 0)])

      result = client.split_pane(session_name, :vertical)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'split-window', '-t', session_name, '-v')
    end

    it 'splits the pane horizontally' do
      allow(Open3).to receive(:capture3).with('tmux', 'split-window', '-t', session_name, '-h').
        and_return(['', '', double(exitstatus: 0)])

      result = client.split_pane(session_name, :horizontal)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'split-window', '-t', session_name, '-h')
    end

    it 'returns false when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'split-window', '-t', session_name, '-v').
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.split_pane(session_name, :vertical)

      expect(result).to be false
    end
  end

  describe '#select_pane' do
    let(:session_name) { 'soba-test-session' }
    let(:pane_index) { 0 }

    it 'selects the specified pane' do
      allow(Open3).to receive(:capture3).with('tmux', 'select-pane', '-t', "#{session_name}.#{pane_index}").
        and_return(['', '', double(exitstatus: 0)])

      result = client.select_pane(session_name, pane_index)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'select-pane', '-t', "#{session_name}.#{pane_index}")
    end

    it 'returns false when pane does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'select-pane', '-t', "#{session_name}.#{pane_index}").
        and_return(['', "can't find pane", double(exitstatus: 1)])

      result = client.select_pane(session_name, pane_index)

      expect(result).to be false
    end
  end

  describe '#resize_pane' do
    let(:session_name) { 'soba-test-session' }

    it 'resizes the pane by direction' do
      allow(Open3).to receive(:capture3).with('tmux', 'resize-pane', '-t', session_name, '-D', '10').
        and_return(['', '', double(exitstatus: 0)])

      result = client.resize_pane(session_name, :down, 10)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'resize-pane', '-t', session_name, '-D', '10')
    end

    it 'supports all directions' do
      directions = { up: '-U', down: '-D', left: '-L', right: '-R' }

      directions.each do |direction, flag|
        allow(Open3).to receive(:capture3).with('tmux', 'resize-pane', '-t', session_name, flag, '5').
          and_return(['', '', double(exitstatus: 0)])

        result = client.resize_pane(session_name, direction, 5)
        expect(result).to be true
      end
    end
  end

  describe '#close_pane' do
    let(:session_name) { 'soba-test-session' }
    let(:pane_index) { 1 }

    it 'closes the specified pane' do
      allow(Open3).to receive(:capture3).with('tmux', 'kill-pane', '-t', "#{session_name}.#{pane_index}").
        and_return(['', '', double(exitstatus: 0)])

      result = client.close_pane(session_name, pane_index)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'kill-pane', '-t', "#{session_name}.#{pane_index}")
    end

    it 'returns false when pane does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'kill-pane', '-t', "#{session_name}.#{pane_index}").
        and_return(['', "can't find pane", double(exitstatus: 1)])

      result = client.close_pane(session_name, pane_index)

      expect(result).to be false
    end
  end

  describe '#session_info' do
    let(:session_name) { 'soba-test-session' }

    it 'returns session details' do
      session_output = "soba-test-session: 1 windows (created Mon Dec 15 10:00:00 2024)\n[120x45]"
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions', '-F', '#{session_name}: #{session_windows} windows (created #{session_created_string}) [#{session_width}x#{session_height}]').
        and_return([session_output, '', double(exitstatus: 0)])

      result = client.session_info(session_name)

      expect(result).to include(
        name: 'soba-test-session',
        windows: 1,
        created_at: 'Mon Dec 15 10:00:00 2024',
        size: [120, 45]
      )
    end

    it 'returns nil when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions', '-F', '#{session_name}: #{session_windows} windows (created #{session_created_string}) [#{session_width}x#{session_height}]').
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.session_info(session_name)

      expect(result).to be_nil
    end
  end

  describe '#active_session' do
    it 'returns the active session name' do
      allow(Open3).to receive(:capture3).with('tmux', 'display-message', '-p', '#{session_name}').
        and_return(['soba-active-session', '', double(exitstatus: 0)])

      result = client.active_session

      expect(result).to eq('soba-active-session')
    end

    it 'returns nil when no active session' do
      allow(Open3).to receive(:capture3).with('tmux', 'display-message', '-p', '#{session_name}').
        and_return(['', 'no current client', double(exitstatus: 1)])

      result = client.active_session

      expect(result).to be_nil
    end
  end

  describe '#session_attached?' do
    let(:session_name) { 'soba-test-session' }

    it 'returns true when session is attached' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions', '-F', '#{session_name}: #{session_attached}', '-f', "#{session_name}==#{session_name}").
        and_return(["soba-test-session: 1", '', double(exitstatus: 0)])

      result = client.session_attached?(session_name)

      expect(result).to be true
    end

    it 'returns false when session is not attached' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions', '-F', '#{session_name}: #{session_attached}', '-f', "#{session_name}==#{session_name}").
        and_return(["soba-test-session: 0", '', double(exitstatus: 0)])

      result = client.session_attached?(session_name)

      expect(result).to be false
    end

    it 'returns false when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions', '-F', '#{session_name}: #{session_attached}', '-f', "#{session_name}==#{session_name}").
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.session_attached?(session_name)

      expect(result).to be false
    end
  end

  describe '#find_pane' do
    let(:session_name) { 'soba-21' }

    it 'returns pane ID for existing session' do
      pane_list = "%10\n%11\n%12"
      allow(Open3).to receive(:capture3).with('tmux', 'list-panes', '-t', session_name, '-F', '#{pane_id}').
        and_return([pane_list, '', double(exitstatus: 0)])

      result = client.find_pane(session_name)

      expect(result).to eq('%10')
    end

    it 'returns nil when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-panes', '-t', session_name, '-F', '#{pane_id}').
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.find_pane(session_name)

      expect(result).to be_nil
    end
  end

  describe '#capture_pane_continuous' do
    let(:pane_id) { '%10' }

    it 'yields captured output continuously' do
      outputs = []
      initial_content = "initial line\n"
      new_content = "initial line\nnew line\n"

      # Mock three capture calls
      allow(Open3).to receive(:capture3).with('tmux', 'capture-pane', '-t', pane_id, '-p', '-S', '-').
        and_return([initial_content, '', double(exitstatus: 0)],
                   [new_content, '', double(exitstatus: 0)],
                   [new_content, '', double(exitstatus: 0)])

      # Allow first sleep, then raise StopIteration on second
      sleep_count = 0
      allow(client).to receive(:sleep).with(1) do
        sleep_count += 1
        raise StopIteration if sleep_count >= 2
      end

      begin
        client.capture_pane_continuous(pane_id) do |output|
          outputs << output
        end
      rescue StopIteration
        # Expected - stop the loop
      end

      expect(outputs).to eq(["initial line\n", "new line\n"])
    end

    it 'stops when pane no longer exists' do
      allow(Open3).to receive(:capture3).with('tmux', 'capture-pane', '-t', pane_id, '-p', '-S', '-').
        and_return(['', "can't find pane", double(exitstatus: 1)])

      expect { |b| client.capture_pane_continuous(pane_id, &b) }.not_to yield_control
    end
  end

  describe '#list_soba_sessions' do
    it 'returns only soba sessions' do
      session_list = "soba-21: 1 windows\nsoba-22: 2 windows\nother-session: 1 windows"
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions').
        and_return([session_list, '', double(exitstatus: 0)])

      result = client.list_soba_sessions

      expect(result).to eq(['soba-21', 'soba-22'])
    end

    it 'returns empty array when no soba sessions exist' do
      session_list = "other-session: 1 windows\nanother-session: 2 windows"
      allow(Open3).to receive(:capture3).with('tmux', 'list-sessions').
        and_return([session_list, '', double(exitstatus: 0)])

      result = client.list_soba_sessions

      expect(result).to eq([])
    end
  end

  describe '#window_exists?' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }

    it 'returns true when window exists' do
      windows_list = "0: bash* (1 panes) [80x24]\n1: test-window (1 panes) [80x24]"
      allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
        and_return([windows_list, '', double(exitstatus: 0)])

      result = client.window_exists?(session_name, window_name)

      expect(result).to be true
    end

    it 'returns false when window does not exist' do
      windows_list = "0: bash* (1 panes) [80x24]\n1: other-window (1 panes) [80x24]"
      allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
        and_return([windows_list, '', double(exitstatus: 0)])

      result = client.window_exists?(session_name, window_name)

      expect(result).to be false
    end

    it 'returns false when session does not exist' do
      allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
        and_return(['', "can't find session", double(exitstatus: 1)])

      result = client.window_exists?(session_name, window_name)

      expect(result).to be false
    end

    context 'edge cases for window name matching' do
      it 'does not match partial window names' do
        windows_list = "0: test-window-2* (1 panes) [80x24]\n1: my-test-window (1 panes) [80x24]"
        allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
          and_return([windows_list, '', double(exitstatus: 0)])

        result = client.window_exists?(session_name, window_name)

        expect(result).to be false
      end

      it 'matches exact window name with issue prefix' do
        window_name = 'issue-58'
        windows_list = "0: issue-58* (1 panes) [80x24]\n1: issue-58-2 (1 panes) [80x24]"
        allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
          and_return([windows_list, '', double(exitstatus: 0)])

        result = client.window_exists?(session_name, window_name)

        expect(result).to be true
      end

      it 'handles window names with special characters' do
        window_name = 'issue-58'
        windows_list = "0: bash* (1 panes) [80x24]\n1: issue-58 (2 panes) [80x24]\n2: issue-58-backup (1 panes) [80x24]"
        allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
          and_return([windows_list, '', double(exitstatus: 0)])

        result = client.window_exists?(session_name, window_name)

        expect(result).to be true
      end

      it 'correctly identifies duplicate window names' do
        window_name = 'issue-58'
        windows_list = "0: issue-58 (1 panes) [80x24]\n1: issue-58 (1 panes) [80x24]"
        allow(Open3).to receive(:capture3).with('tmux', 'list-windows', '-t', session_name).
          and_return([windows_list, '', double(exitstatus: 0)])

        result = client.window_exists?(session_name, window_name)

        expect(result).to be true
      end
    end
  end

  describe '#split_window' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }

    it 'splits window vertically and returns pane ID' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'split-window', '-t', "#{session_name}:#{window_name}",
        '-v', '-P', '-F', '#{pane_id}'
      ).and_return(['%12', '', double(exitstatus: 0)])

      result = client.split_window(
        session_name: session_name,
        window_name: window_name,
        vertical: true
      )

      expect(result).to eq('%12')
    end

    it 'splits window horizontally and returns pane ID' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'split-window', '-t', "#{session_name}:#{window_name}",
        '-h', '-P', '-F', '#{pane_id}'
      ).and_return(['%13', '', double(exitstatus: 0)])

      result = client.split_window(
        session_name: session_name,
        window_name: window_name,
        vertical: false
      )

      expect(result).to eq('%13')
    end

    it 'returns nil when split fails' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'split-window', '-t', "#{session_name}:#{window_name}",
        '-v', '-P', '-F', '#{pane_id}'
      ).and_return(['', "can't find window", double(exitstatus: 1)])

      result, error = client.split_window(
        session_name: session_name,
        window_name: window_name,
        vertical: true
      )

      expect(result).to be_nil
      expect(error).to be_a(Hash)
    end

    context 'with error details' do
      it 'returns error details when split fails' do
        error_message = "can't find window: soba-test-session:test-window"
        allow(Open3).to receive(:capture3).with(
          'tmux', 'split-window', '-t', "#{session_name}:#{window_name}",
          '-v', '-P', '-F', '#{pane_id}'
        ).and_return(['', error_message, double(exitstatus: 1)])

        result, error = client.split_window(
          session_name: session_name,
          window_name: window_name,
          vertical: true
        )

        expect(result).to be_nil
        expect(error).to include(:stderr)
        expect(error[:stderr]).to eq(error_message)
        expect(error[:command]).to eq(['tmux', 'split-window', '-t', "#{session_name}:#{window_name}", '-v', '-P', '-F', '#{pane_id}'])
        expect(error[:exit_status]).to eq(1)
      end

      it 'returns error details for pane limit exceeded' do
        error_message = "create pane failed: pane too small"
        allow(Open3).to receive(:capture3).with(
          'tmux', 'split-window', '-t', "#{session_name}:#{window_name}",
          '-v', '-P', '-F', '#{pane_id}'
        ).and_return(['', error_message, double(exitstatus: 1)])

        result, error = client.split_window(
          session_name: session_name,
          window_name: window_name,
          vertical: true
        )

        expect(result).to be_nil
        expect(error[:stderr]).to eq(error_message)
      end
    end
  end

  describe '#list_panes' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }

    it 'returns list of panes with creation times' do
      pane_list = "%0:1734444000\n%1:1734444100\n%2:1734444200"
      allow(Open3).to receive(:capture3).with(
        'tmux', 'list-panes', '-t', "#{session_name}:#{window_name}",
        '-F', '#{pane_id}:#{pane_start_time}'
      ).and_return([pane_list, '', double(exitstatus: 0)])

      result = client.list_panes(session_name, window_name)

      expect(result).to eq([
        { id: '%0', start_time: 1734444000 },
        { id: '%1', start_time: 1734444100 },
        { id: '%2', start_time: 1734444200 },
      ])
    end

    it 'returns empty array when window does not exist' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'list-panes', '-t', "#{session_name}:#{window_name}",
        '-F', '#{pane_id}:#{pane_start_time}'
      ).and_return(['', "can't find window", double(exitstatus: 1)])

      result = client.list_panes(session_name, window_name)

      expect(result).to eq([])
    end
  end

  describe '#kill_pane' do
    let(:pane_id) { '%0' }

    it 'kills the specified pane' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'kill-pane', '-t', pane_id
      ).and_return(['', '', double(exitstatus: 0)])

      result = client.kill_pane(pane_id)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with('tmux', 'kill-pane', '-t', pane_id)
    end

    it 'returns false when pane does not exist' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'kill-pane', '-t', pane_id
      ).and_return(['', "can't find pane", double(exitstatus: 1)])

      result = client.kill_pane(pane_id)

      expect(result).to be false
    end
  end

  describe '#select_layout' do
    let(:session_name) { 'soba-test-session' }
    let(:window_name) { 'test-window' }
    let(:layout) { 'even-horizontal' }

    it 'applies the specified layout' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'select-layout', '-t', "#{session_name}:#{window_name}", layout
      ).and_return(['', '', double(exitstatus: 0)])

      result = client.select_layout(session_name, window_name, layout)

      expect(result).to be true
      expect(Open3).to have_received(:capture3).with(
        'tmux', 'select-layout', '-t', "#{session_name}:#{window_name}", layout
      )
    end

    it 'returns false when window does not exist' do
      allow(Open3).to receive(:capture3).with(
        'tmux', 'select-layout', '-t', "#{session_name}:#{window_name}", layout
      ).and_return(['', "can't find window", double(exitstatus: 1)])

      result = client.select_layout(session_name, window_name, layout)

      expect(result).to be false
    end
  end
end