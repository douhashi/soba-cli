# frozen_string_literal: true

require 'spec_helper'
require_relative '../../spec/support/tmux_cleanup_helper'

RSpec.describe TmuxCleanupHelper do
  include TmuxCleanupHelper

  let(:tmux_client) { instance_double('Soba::Tmux::TmuxClient') }

  describe '#cleanup_test_tmux_sessions' do
    context 'when SOBA_TEST_MODE is true' do
      before do
        ENV['SOBA_TEST_MODE'] = 'true'
      end

      after do
        ENV.delete('SOBA_TEST_MODE')
      end

      it 'removes only test sessions' do
        sessions = [
          'soba-test-repo-12345',
          'soba-test-repo-67890',
          'soba-production-12345',
          'other-session',
        ]

        allow(tmux_client).to receive(:list_sessions).and_return(sessions)
        expect(tmux_client).to receive(:kill_session).with('soba-test-repo-12345')
        expect(tmux_client).to receive(:kill_session).with('soba-test-repo-67890')
        expect(tmux_client).not_to receive(:kill_session).with('soba-production-12345')
        expect(tmux_client).not_to receive(:kill_session).with('other-session')

        cleanup_test_tmux_sessions(tmux_client)
      end

      it 'handles errors gracefully' do
        allow(tmux_client).to receive(:list_sessions).and_raise(StandardError.new('Connection error'))

        expect { cleanup_test_tmux_sessions(tmux_client) }.not_to raise_error
      end
    end

    context 'when SOBA_TEST_MODE is not set' do
      before do
        ENV.delete('SOBA_TEST_MODE')
      end

      it 'does not clean up any sessions' do
        allow(tmux_client).to receive(:list_sessions).and_return(['soba-test-repo-12345'])
        expect(tmux_client).not_to receive(:kill_session)

        cleanup_test_tmux_sessions(tmux_client)
      end
    end
  end

  describe '#cleanup_specific_test_session' do
    context 'when SOBA_TEST_MODE is true' do
      before do
        ENV['SOBA_TEST_MODE'] = 'true'
      end

      after do
        ENV.delete('SOBA_TEST_MODE')
      end

      it 'removes specific test session if it exists' do
        session_name = 'soba-test-repo-12345'
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(true)
        expect(tmux_client).to receive(:kill_session).with(session_name)

        cleanup_specific_test_session(tmux_client, session_name)
      end

      it 'does not attempt to remove non-existent session' do
        session_name = 'soba-test-repo-12345'
        allow(tmux_client).to receive(:session_exists?).with(session_name).and_return(false)
        expect(tmux_client).not_to receive(:kill_session)

        cleanup_specific_test_session(tmux_client, session_name)
      end

      it 'refuses to remove non-test sessions' do
        session_name = 'soba-production-12345'
        expect(tmux_client).not_to receive(:session_exists?)
        expect(tmux_client).not_to receive(:kill_session)

        cleanup_specific_test_session(tmux_client, session_name)
      end

      it 'handles errors gracefully' do
        session_name = 'soba-test-repo-12345'
        allow(tmux_client).to receive(:session_exists?).and_raise(StandardError.new('Connection error'))

        expect { cleanup_specific_test_session(tmux_client, session_name) }.not_to raise_error
      end
    end
  end

  describe '#ensure_only_test_sessions' do
    context 'when SOBA_TEST_MODE is true' do
      before do
        ENV['SOBA_TEST_MODE'] = 'true'
      end

      after do
        ENV.delete('SOBA_TEST_MODE')
      end

      it 'warns about non-test soba sessions' do
        sessions = [
          'soba-test-repo-12345',
          'soba-production-12345',
          'soba-development-67890',
          'other-session',
        ]

        allow(tmux_client).to receive(:list_sessions).and_return(sessions)

        expect { ensure_only_test_sessions(tmux_client) }.
          to output(/Found non-test soba sessions.*soba-production-12345.*soba-development-67890/).to_stdout
      end

      it 'does not warn when only test sessions exist' do
        sessions = [
          'soba-test-repo-12345',
          'soba-test-repo-67890',
          'other-session',
        ]

        allow(tmux_client).to receive(:list_sessions).and_return(sessions)

        expect { ensure_only_test_sessions(tmux_client) }.
          not_to output(/Found non-test soba sessions/).to_stdout
      end
    end
  end
end