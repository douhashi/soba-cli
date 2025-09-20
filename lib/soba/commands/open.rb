# frozen_string_literal: true

require_relative '../configuration'
require_relative '../services/tmux_session_manager'
require_relative '../infrastructure/tmux_client'

module Soba
  module Commands
    class Open
      class SessionNotFoundError < StandardError; end

      def initialize
        @tmux_client = Infrastructure::TmuxClient.new
        @tmux_session_manager = Services::TmuxSessionManager.new(config: nil, tmux_client: @tmux_client)
      end

      def execute(issue_number, options = {})
        validate_tmux_installation!

        if options[:list]
          list_issue_sessions
        elsif issue_number
          open_issue_session(issue_number)
        else
          open_repository_session
        end
      end

      private

      def validate_tmux_installation!
        unless @tmux_client.tmux_installed?
          raise Infrastructure::TmuxNotInstalled, 'tmux is not installed. Please install tmux and try again'
        end
      end

      def open_repository_session
        Configuration.load!

        repository = Configuration.config.github.repository

        unless repository
          raise ArgumentError, 'GitHub repository is not configured. Please run "soba init" first.'
        end

        # First, try standard session search (new format without PID)
        result = @tmux_session_manager.find_repository_session

        unless result[:success]
          raise ArgumentError, result[:error]
        end

        if result[:exists]
          session_name = result[:session_name]
          puts "Attaching to repository session #{session_name}..."
          @tmux_client.attach_to_session(session_name)
        else
          # Fallback to find repository session by PID (for backward compatibility)
          pid_result = @tmux_session_manager.find_repository_session_by_pid(repository)

          if pid_result[:exists]
            session_name = pid_result[:session_name]
            puts "Attaching to repository session #{session_name}... (legacy format)"
            @tmux_client.attach_to_session(session_name)
          else
            raise SessionNotFoundError, <<~MESSAGE
              Repository session not found.

              A session will be created automatically when you start the workflow:
                soba start

              Or check active sessions:
                soba open --list
            MESSAGE
          end
        end
      end

      def open_issue_session(issue_number)
        Configuration.load!
        repository = Configuration.config.github.repository

        unless repository
          raise ArgumentError, 'GitHub repository is not configured. Please run "soba init" first.'
        end

        # Convert repository format (e.g., "user/repo" -> "user-repo")
        repository_name = repository.gsub(/[\/._]/, '-')
        window_id = @tmux_session_manager.find_issue_window(repository_name, issue_number)

        if window_id
          puts "Attaching to Issue ##{issue_number} session..."
          @tmux_client.attach_to_window(window_id)
        else
          raise SessionNotFoundError, <<~MESSAGE
            Issue ##{issue_number} session not found.

            To start a session:
              soba start #{issue_number}

            To check active sessions:
              soba open --list
          MESSAGE
        end
      end

      def list_issue_sessions
        Configuration.load!
        repository = Configuration.config.github.repository

        unless repository
          raise ArgumentError, 'GitHub repository is not configured. Please run "soba init" first.'
        end

        # Convert repository format (e.g., "user/repo" -> "user-repo")
        repository_name = repository.gsub(/[\/._]/, '-')
        sessions = @tmux_session_manager.list_issue_windows(repository_name)

        if sessions.empty?
          puts 'No active Issue sessions'
          puts
          puts 'To start a session:'
          puts '  soba start <issue-number>'
        else
          puts 'Active Issue sessions:'
          puts
          sessions.each do |session|
            issue_number = extract_issue_number(session[:window])
            title = session[:title] || '(fetching title...)'
            puts "  ##{issue_number.ljust(6)} #{title}"
          end
          puts
          puts 'To open a session:'
          puts '  soba open <issue-number>'
        end
      end

      def extract_issue_number(window_name)
        match = window_name.match(/issue-(\d+)/)
        match ? match[1] : window_name
      end
    end
  end
end