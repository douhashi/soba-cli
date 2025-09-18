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
          raise ArgumentError, 'Issue番号を指定するか、--listオプションを使用してください'
        end
      end

      private

      def validate_tmux_installation!
        unless @tmux_client.tmux_installed?
          raise Infrastructure::TmuxNotInstalled, 'tmuxがインストールされていません。インストールしてから再度お試しください'
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
          puts "Issue ##{issue_number} のセッションにアタッチします..."
          @tmux_client.attach_to_window(window_id)
        else
          raise SessionNotFoundError, <<~MESSAGE
            Issue ##{issue_number} のセッションが見つかりません。

            セッションを開始するには:
              soba start #{issue_number}

            アクティブなセッションを確認するには:
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
          puts 'アクティブなIssueセッションがありません'
          puts
          puts 'セッションを開始するには:'
          puts '  soba start <issue-number>'
        else
          puts 'アクティブなIssueセッション:'
          puts
          sessions.each do |session|
            issue_number = extract_issue_number(session[:window])
            title = session[:title] || '(タイトル取得中...)'
            puts "  ##{issue_number.ljust(6)} #{title}"
          end
          puts
          puts 'セッションを開くには:'
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