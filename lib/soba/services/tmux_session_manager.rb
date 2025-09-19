# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require_relative '../configuration'
require_relative '../infrastructure/lock_manager'
require_relative '../infrastructure/tmux_client'
require_relative 'test_process_manager'

module Soba
  module Services
    class TmuxSessionManager
      def initialize(config: nil, tmux_client: nil, lock_manager: nil, test_process_manager: nil)
        @config = config
        @tmux_client = tmux_client || Soba::Infrastructure::TmuxClient.new
        @lock_manager = lock_manager || Soba::Infrastructure::LockManager.new
        @test_process_manager = test_process_manager || TestProcessManager.new
      end

      def find_or_create_repository_session
        repository = Configuration.config.github.repository

        return { success: false, error: 'Repository configuration not found' } if repository.blank?

        # Convert repository name to session-safe format with PID
        session_name = generate_session_name(repository)

        if @tmux_client.session_exists?(session_name)
          { success: true, session_name: session_name, created: false }
        else
          if @tmux_client.create_session(session_name)
            { success: true, session_name: session_name, created: true }
          else
            { success: false, error: 'Failed to create repository session' }
          end
        end
      end

      def find_repository_session
        repository = Configuration.config.github.repository

        return { success: false, error: 'Repository configuration not found' } if repository.blank?

        # Convert repository name to session-safe format with PID
        session_name = generate_session_name(repository)

        if @tmux_client.session_exists?(session_name)
          { success: true, session_name: session_name, exists: true }
        else
          { success: true, session_name: session_name, exists: false }
        end
      end

      def create_issue_window(session_name:, issue_number:)
        window_name = "issue-#{issue_number}"
        lock_name = "window-#{session_name}-#{window_name}"

        @lock_manager.with_lock(lock_name, timeout: 5) do
          # Double check for existing window to prevent duplicates
          if @tmux_client.window_exists?(session_name, window_name)
            { success: true, window_name: window_name, created: false }
          else
            if @tmux_client.create_window(session_name, window_name)
              # Verify creation was successful
              if @tmux_client.window_exists?(session_name, window_name)
                { success: true, window_name: window_name, created: true }
              else
                { success: false, error: "Window creation verification failed for issue #{issue_number}" }
              end
            else
              { success: false, error: "Failed to create window for issue #{issue_number}" }
            end
          end
        end
      rescue Soba::Infrastructure::LockTimeoutError => e
        { success: false, error: "Lock acquisition failed: #{e.message}" }
      end

      def create_phase_pane(session_name:, window_name:, phase:, vertical: true, max_panes: 3, max_retries: 3)
        # 前提条件チェック
        unless @tmux_client.session_exists?(session_name)
          return { success: false, error: "Session does not exist: #{session_name}" }
        end

        unless @tmux_client.window_exists?(session_name, window_name)
          return { success: false, error: "Window does not exist: #{window_name}" }
        end

        # tmuxサーバーの応答性チェック
        if @tmux_client.list_sessions.nil?
          return { success: false, error: 'tmux server is not responding' }
        end

        # 現在のペイン一覧を取得
        existing_panes = @tmux_client.list_panes(session_name, window_name)

        # 最大ペイン数を超えている場合、古いペインを削除
        if existing_panes.size >= max_panes
          # start_timeでソート（古い順）
          sorted_panes = existing_panes.sort_by { |p| p[:start_time] }

          # 最大ペイン数-1になるまで古いペインを削除
          panes_to_remove = sorted_panes.take(existing_panes.size - max_panes + 1)
          panes_to_remove.each do |pane|
            @tmux_client.kill_pane(pane[:id])
          end
        end

        # リトライロジック付きでペインを作成
        pane_id = nil
        error_details = nil
        retry_count = 0
        retry_delays = [0.5, 1, 2] # 指数バックオフ

        max_retries.times do |attempt|
          result = @tmux_client.split_window(
            session_name: session_name,
            window_name: window_name,
            vertical: vertical
          )

          # 結果を確認
          if result.is_a?(Array)
            pane_id, error_details = result
          else
            pane_id = result
          end

          if pane_id
            # 成功した場合はループを抜ける
            break
          else
            retry_count = attempt + 1
            if error_details && retry_count < max_retries
              Soba.logger.warn(
                "Pane creation failed (attempt #{retry_count}/#{max_retries}): " \
                "#{error_details[:stderr]} (exit status: #{error_details[:exit_status]})"
              )
              sleep(retry_delays[attempt] || 2)
            end
          end
        end

        if pane_id
          # レイアウトを調整
          @tmux_client.select_layout(session_name, window_name, 'even-horizontal')

          { success: true, pane_id: pane_id, phase: phase }
        else
          error_message = "Failed to create pane for phase #{phase}"
          if error_details
            error_message += ": #{error_details[:stderr]}"
            Soba.logger.error(
              "Pane creation failed after #{retry_count} retries: " \
              "#{error_details[:stderr]} (exit status: #{error_details[:exit_status]})"
            )
          end
          { success: false, error: error_message }
        end
      end

      def find_issue_window(repository_name, issue_number)
        session_name = generate_session_name(repository_name)
        window_name = "issue-#{issue_number}"

        if @tmux_client.session_exists?(session_name) && @tmux_client.window_exists?(session_name, window_name)
          "#{session_name}:#{window_name}"
        else
          nil
        end
      end

      def list_issue_windows(repository_name)
        session_name = generate_session_name(repository_name)

        return [] unless @tmux_client.session_exists?(session_name)

        windows = @tmux_client.list_windows(session_name)
        issue_windows = windows.select { |window| window.start_with?('issue-') }

        issue_windows.map do |window|
          issue_number = begin
                           window.match(/issue-(\d+)/)[1]
                         rescue
                           nil
                         end
          next unless issue_number

          # Try to fetch issue title from GitHub
          title = begin
                    fetch_issue_title(repository_name, issue_number)
                  rescue
                    nil
                  end

          {
            window: window,
            title: title,
          }
        end.compact
      end

      private

      # Generate session name with PID for process isolation
      def generate_session_name(repository)
        if @test_process_manager.test_mode?
          @test_process_manager.generate_test_session_name(repository)
        else
          "soba-#{repository.gsub(/[\/._]/, '-')}-#{Process.pid}"
        end
      end

      def fetch_issue_title(repository_name, issue_number)
        # This is a placeholder - actual implementation would use GitHub API
        # For now, return nil to let the command handle it
        nil
      end
    end
  end
end