# frozen_string_literal: true

require 'spec_helper'
require 'soba/infrastructure/tmux_client'
require 'soba/services/test_process_manager'
require 'soba/services/tmux_session_manager'

RSpec.describe 'Test Process Isolation' do
  let(:tmux_client) { Soba::Infrastructure::TmuxClient.new }
  let(:test_process_manager) { Soba::Services::TestProcessManager.new }

  describe 'test mode session isolation', test_process_isolation: true do
    before do
      ENV['SOBA_TEST_MODE'] = 'true'
    end

    after do
      ENV.delete('SOBA_TEST_MODE')
      # Clean up any test sessions created during the test
      tmux_client.list_sessions.each do |session|
        if session.start_with?('soba-test-')
          tmux_client.kill_session(session)
        end
      end
    end

    it 'creates test sessions with soba-test- prefix in test mode' do
      repository = 'test/repo'
      session_name = test_process_manager.generate_test_session_name(repository)

      expect(session_name).to start_with('soba-test-')
      expect(session_name).to include('test-repo')
      expect(session_name).to include(Process.pid.to_s)
    end

    it 'list_soba_sessions returns only test sessions in test mode' do
      # Create a mix of sessions
      test_session1 = 'soba-test-repo1-12345-abcd'
      test_session2 = 'soba-test-repo2-12345-efgh'
      regular_session = 'soba-regular-12345'

      # Skip if sessions already exist
      unless tmux_client.session_exists?(test_session1)
        tmux_client.create_session(test_session1)
      end
      unless tmux_client.session_exists?(test_session2)
        tmux_client.create_session(test_session2)
      end
      unless tmux_client.session_exists?(regular_session)
        tmux_client.create_session(regular_session)
      end

      # In test mode, should only see test sessions
      soba_sessions = tmux_client.list_soba_sessions

      expect(soba_sessions).to include(test_session1)
      expect(soba_sessions).to include(test_session2)
      expect(soba_sessions).not_to include(regular_session)

      # Clean up
      tmux_client.kill_session(test_session1)
      tmux_client.kill_session(test_session2)
      tmux_client.kill_session(regular_session)
    end

    it 'does not affect regular soba sessions when in test mode' do
      # Temporarily switch out of test mode to create regular session
      ENV.delete('SOBA_TEST_MODE')
      regular_session = 'soba-production-99999'
      tmux_client.create_session(regular_session) unless tmux_client.session_exists?(regular_session)

      # Switch back to test mode
      ENV['SOBA_TEST_MODE'] = 'true'
      test_session = 'soba-test-temp-12345-xyz'
      tmux_client.create_session(test_session) unless tmux_client.session_exists?(test_session)

      # list_soba_sessions should only return test sessions
      soba_sessions = tmux_client.list_soba_sessions

      expect(soba_sessions).to include(test_session)
      expect(soba_sessions).not_to include(regular_session)

      # Clean up both sessions
      tmux_client.kill_session(test_session) if tmux_client.session_exists?(test_session)
      tmux_client.kill_session(regular_session) if tmux_client.session_exists?(regular_session)
    end
  end

  describe 'regular mode session isolation' do
    before do
      ENV.delete('SOBA_TEST_MODE')
    end

    after do
      # Clean up only specific test sessions created during this test
      tmux_client.list_sessions.each do |session|
        # Only clean up the specific sessions we created for testing
        if session == 'soba-test-repo-12345-abcd' ||
           session == 'soba-regular-12345' ||
           session == 'soba-production-67890'
          begin
            tmux_client.kill_session(session)
          rescue
            nil
          end
        end
      end
    end

    it 'list_soba_sessions excludes test sessions in regular mode' do
      # Create a mix of sessions
      test_session = 'soba-test-repo-12345-abcd'
      regular_session1 = 'soba-regular-12345'
      regular_session2 = 'soba-production-67890'

      tmux_client.create_session(test_session) unless tmux_client.session_exists?(test_session)
      tmux_client.create_session(regular_session1) unless tmux_client.session_exists?(regular_session1)
      tmux_client.create_session(regular_session2) unless tmux_client.session_exists?(regular_session2)

      # In regular mode, should exclude test sessions
      soba_sessions = tmux_client.list_soba_sessions

      expect(soba_sessions).not_to include(test_session)
      expect(soba_sessions).to include(regular_session1)
      expect(soba_sessions).to include(regular_session2)

      # Clean up
      tmux_client.kill_session(test_session) if tmux_client.session_exists?(test_session)
      tmux_client.kill_session(regular_session1) if tmux_client.session_exists?(regular_session1)
      tmux_client.kill_session(regular_session2) if tmux_client.session_exists?(regular_session2)
    end
  end

  describe 'TmuxSessionManager integration' do
    let(:tmux_session_manager) do
      Soba::Services::TmuxSessionManager.new(
        tmux_client: tmux_client,
        test_process_manager: test_process_manager
      )
    end

    before do
      allow(Soba::Configuration).to receive(:config).and_return(
        double(github: double(repository: 'owner/integration-repo'))
      )
    end

    after do
      # Clean up only test sessions created during the test
      tmux_client.list_sessions.each do |session|
        if session.start_with?('soba-test-')
          begin
            tmux_client.kill_session(session)
          rescue
            nil
          end
        end
      end
    end

    context 'in test mode' do
      before do
        ENV['SOBA_TEST_MODE'] = 'true'
      end

      after do
        ENV.delete('SOBA_TEST_MODE')
      end

      it 'creates sessions with test prefix through TmuxSessionManager' do
        result = tmux_session_manager.find_or_create_repository_session

        expect(result[:success]).to be true
        expect(result[:session_name]).to start_with('soba-test-')
        expect(result[:session_name]).to include('owner-integration-repo')

        # Verify the session was actually created
        expect(tmux_client.session_exists?(result[:session_name])).to be true

        # Clean up
        tmux_client.kill_session(result[:session_name])
      end
    end

    context 'in regular mode' do
      it 'test process manager distinguishes between test and regular mode' do
        # Create a new test process manager for regular mode
        regular_test_manager = Soba::Services::TestProcessManager.new

        # Ensure environment is in regular mode
        ENV.delete('SOBA_TEST_MODE')

        # Create a new session manager with the regular test manager
        regular_session_manager = Soba::Services::TmuxSessionManager.new(
          tmux_client: tmux_client,
          test_process_manager: regular_test_manager
        )

        # Regular mode should not use test prefix
        expect(regular_test_manager.test_mode?).to be false

        result = regular_session_manager.find_or_create_repository_session

        expect(result[:success]).to be true
        expect(result[:session_name]).to start_with('soba-')
        expect(result[:session_name]).not_to start_with('soba-test-')
        expect(result[:session_name]).to eq('soba-owner-integration-repo')

        # Verify the session was actually created
        expect(tmux_client.session_exists?(result[:session_name])).to be true

        # Clean up
        tmux_client.kill_session(result[:session_name])
      end
    end
  end
end