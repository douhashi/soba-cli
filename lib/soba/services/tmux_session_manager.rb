# frozen_string_literal: true

module Soba
  module Services
    class TmuxSessionManager
      SESSION_PREFIX = 'soba-claude'

      def initialize(tmux_client:)
        @tmux_client = tmux_client
      end

      def start_claude_session(issue_number:, command:)
        session_name = generate_session_name(issue_number)

        unless @tmux_client.create_session(session_name)
          return { success: false, error: 'Failed to create tmux session' }
        end

        unless @tmux_client.send_keys(session_name, command)
          @tmux_client.kill_session(session_name)
          return { success: false, error: 'Failed to send command to tmux session' }
        end

        { success: true, session_name: session_name }
      end

      def stop_claude_session(session_name)
        unless @tmux_client.session_exists?(session_name)
          return { success: true, message: 'Session not found (already stopped)' }
        end

        if @tmux_client.kill_session(session_name)
          { success: true }
        else
          { success: false, error: 'Failed to kill session' }
        end
      end

      def get_session_status(session_name)
        exists = @tmux_client.session_exists?(session_name)

        if exists
          output = @tmux_client.capture_pane(session_name)
          {
            exists: true,
            status: 'running',
            last_output: output,
          }
        else
          {
            exists: false,
            status: 'stopped',
            last_output: nil,
          }
        end
      end

      def attach_to_session(session_name)
        unless @tmux_client.session_exists?(session_name)
          return { success: false, error: 'Session not found' }
        end

        { success: true, command: "tmux attach-session -t #{session_name}" }
      end

      def list_claude_sessions
        all_sessions = @tmux_client.list_sessions
        all_sessions.select { |session| session.start_with?("#{SESSION_PREFIX}-") }
      end

      def cleanup_old_sessions(max_age_seconds: 3600)
        current_time = Time.now.to_i
        cleaned_sessions = []

        list_claude_sessions.each do |session_name|
          # Extract timestamp from session name
          if session_name =~ /#{SESSION_PREFIX}-\d+-(\d+)$/
            session_timestamp = Regexp.last_match(1).to_i
            age = current_time - session_timestamp

            if age > max_age_seconds
              @tmux_client.kill_session(session_name)
              cleaned_sessions << session_name
            end
          end
        end

        { cleaned: cleaned_sessions }
      end

      private

      def generate_session_name(issue_number)
        timestamp = Time.now.to_i
        "#{SESSION_PREFIX}-#{issue_number}-#{timestamp}"
      end
    end
  end
end