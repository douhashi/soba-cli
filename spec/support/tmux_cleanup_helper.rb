# frozen_string_literal: true

module TmuxCleanupHelper
  def cleanup_test_tmux_sessions(tmux_client)
    return unless ENV['SOBA_TEST_MODE'] == 'true'

    tmux_client.list_sessions.each do |session|
      if session.start_with?('soba-test-')
        tmux_client.kill_session(session)
      end
    end
  rescue StandardError => e
    puts "Warning: Failed to cleanup test sessions: #{e.message}"
  end

  def cleanup_specific_test_session(tmux_client, session_name)
    return unless ENV['SOBA_TEST_MODE'] == 'true'

    if session_name.start_with?('soba-test-') && tmux_client.session_exists?(session_name)
      tmux_client.kill_session(session_name)
    end
  rescue StandardError => e
    puts "Warning: Failed to cleanup session #{session_name}: #{e.message}"
  end

  def ensure_only_test_sessions(tmux_client)
    return unless ENV['SOBA_TEST_MODE'] == 'true'

    non_test_sessions = tmux_client.list_sessions.reject { |s| s.start_with?('soba-test-') }
    soba_sessions = non_test_sessions.select { |s| s.start_with?('soba-') }

    if soba_sessions.any?
      puts "Warning: Found non-test soba sessions during test cleanup: #{soba_sessions.join(', ')}"
      puts "These sessions will NOT be deleted to protect your development environment."
    end
  end

  def cleanup_all_test_artifacts
    return unless ENV['SOBA_TEST_MODE'] == 'true'

    tmux_client = Soba::Tmux::TmuxClient.new
    cleanup_test_tmux_sessions(tmux_client)
  rescue StandardError => e
    puts "Warning: Failed to cleanup test artifacts: #{e.message}"
  end
end

RSpec.configure do |config|
  config.include TmuxCleanupHelper

  config.after(:suite) do
    if ENV['SOBA_TEST_MODE'] == 'true'
      puts "Cleaning up test tmux sessions..."
      tmux_client = Soba::Tmux::TmuxClient.new
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
  end
end