# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative 'git_workspace_manager'
require_relative 'slack_notifier'
require_relative '../configuration'
require_relative '../config_loader'

module Soba
  module Services
    class WorkflowExecutionError < StandardError; end

    class WorkflowExecutor
      def initialize(tmux_session_manager: nil, git_workspace_manager: nil)
        @tmux_session_manager = tmux_session_manager
        @git_workspace_manager = git_workspace_manager || GitWorkspaceManager.new
      end

      def execute(phase:, issue_number:, use_tmux: true, setup_workspace: true, issue_title: nil, phase_name: nil)
        return nil unless phase.command

        # Slack通知を送信（設定が有効な場合）
        send_slack_notification(issue_number, issue_title, phase_name) if phase_name

        # フェーズ開始時にmainブランチを更新し、ワークスペースをセットアップ
        if setup_workspace
          # mainブランチを最新化
          begin
            @git_workspace_manager.update_main_branch
            puts "Successfully updated main branch"
          rescue GitWorkspaceManager::GitOperationError => e
            puts "Warning: Failed to update main branch: #{e.message}"
            puts "  Continuing without main branch update..."
            # mainブランチの更新に失敗しても続行（エラーハンドリング）
          end

          # ワークスペースをセットアップ
          begin
            @git_workspace_manager.setup_workspace(issue_number)
            puts "Successfully setup workspace for issue ##{issue_number}"
          rescue GitWorkspaceManager::GitOperationError => e
            puts "Warning: Failed to setup workspace: #{e.message}"
            puts "  Continuing without worktree setup..."
            # ワークスペースのセットアップに失敗しても続行（既存の動作を維持）
          end
        end

        if use_tmux
          execute_in_tmux(phase: phase, issue_number: issue_number)
        else
          execute_direct(phase: phase, issue_number: issue_number)
        end
      end

      def execute_direct(phase:, issue_number:)
        return nil unless phase.command

        command_array = build_command(phase, issue_number)
        worktree_path = @git_workspace_manager.get_worktree_path(issue_number)

        result = if worktree_path
                   # worktreeが存在する場合はその中で実行
                   Dir.chdir(worktree_path) do
                     Open3.popen3(*command_array) do |stdin, stdout, stderr, wait_thr|
                       stdin.close
                       [stdout.read, stderr.read, wait_thr.value]
                     end
                   end
                 else
                   # worktreeが存在しない場合は現在のディレクトリで実行
                   Open3.popen3(*command_array) do |stdin, stdout, stderr, wait_thr|
                     stdin.close
                     [stdout.read, stderr.read, wait_thr.value]
                   end
                 end

        stdout, stderr, status = result

        {
          success: status.exitstatus == 0,
          output: stdout,
          error: stderr,
          exit_code: status.exitstatus,
        }
      rescue Errno::ENOENT => e
        raise WorkflowExecutionError, "Failed to execute workflow command: #{e.message}"
      rescue StandardError => e
        raise WorkflowExecutionError, "Failed to execute workflow command: #{e.message}"
      end

      def execute_in_tmux(phase:, issue_number:)
        return nil unless phase.command

        command_string = build_command_string_with_worktree(phase, issue_number)
        puts "Executing in tmux for phase: #{phase.name || 'unknown'}, issue ##{issue_number}"

        begin
          # 新しいtmux管理方式: 1リポジトリ = 1セッション、1 Issue = 1 window
          session_result = @tmux_session_manager.find_or_create_repository_session
          return session_result unless session_result[:success]

          window_result = @tmux_session_manager.create_issue_window(
            session_name: session_result[:session_name],
            issue_number: issue_number
          )
          return window_result unless window_result[:success]

          # フェーズごとにpane分割（既存のwindowがある場合は新規pane作成）
          if window_result[:created]
            # 新規windowの場合は最初のpaneでコマンド実行
            puts "  Created new window: #{window_result[:window_name]}"
            apply_command_delay
            tmux_client = Soba::Infrastructure::TmuxClient.new
            tmux_client.send_keys("#{session_result[:session_name]}:#{window_result[:window_name]}", command_string)
            pane_id = nil
          else
            # 既存windowの場合は新規paneを作成（水平分割）
            phase_name = phase.name || 'unknown'
            puts "  Creating new pane for phase: #{phase_name} in window: #{window_result[:window_name]}"
            pane_result = @tmux_session_manager.create_phase_pane(
              session_name: session_result[:session_name],
              window_name: window_result[:window_name],
              phase: phase_name,
              vertical: false
            )
            return pane_result unless pane_result[:success]

            apply_command_delay
            pane_id = pane_result[:pane_id]
            puts "  Created pane: #{pane_id}"
            tmux_client = Soba::Infrastructure::TmuxClient.new
            tmux_client.send_keys(pane_id, command_string)
          end

          # 監視用コマンドを生成
          target = pane_id || "#{session_result[:session_name]}:#{window_result[:window_name]}"
          monitor_commands = [
            "tmux attach -t #{target}",
            "tmux capture-pane -t #{target} -p",
          ]

          {
            success: true,
            session_name: session_result[:session_name],
            window_name: window_result[:window_name],
            pane_id: pane_id,
            mode: 'tmux',
            tmux_info: {
              session: session_result[:session_name],
              window: window_result[:window_name],
              pane: pane_id,
              monitor_commands: monitor_commands,
            },
          }
        rescue Soba::Infrastructure::TmuxNotInstalled => e
          # tmuxがインストールされていない場合は通常実行にフォールバック
          puts "Warning: #{e.message}. Falling back to direct execution..."
          execute_direct(phase: phase, issue_number: issue_number)
        rescue StandardError => e
          # その他のtmuxエラーの場合も通常実行にフォールバック
          puts "Warning: Tmux execution failed: #{e.message}. Falling back to direct execution..."
          execute_direct(phase: phase, issue_number: issue_number)
        end
      end

      private

      def send_slack_notification(issue_number, issue_title, phase_name)
        return unless ConfigLoader.config.workflow.slack_notifications_enabled

        notifier = SlackNotifier.from_env
        return unless notifier.enabled?

        notifier.notify_phase_start(
          number: issue_number,
          title: issue_title || "Issue ##{issue_number}",
          phase: phase_name
        )
      rescue StandardError => e
        Soba.logger.warn "Failed to send Slack notification: #{e.message}"
      end

      def build_command(phase_config, issue_number)
        command = [phase_config.command]
        command.concat(phase_config.options) if phase_config.options&.any?

        if phase_config.parameter
          parameter = phase_config.parameter.gsub('{{issue-number}}', issue_number.to_s)
          command << parameter
        end

        command
      end

      def build_command_string(phase_config, issue_number)
        command_parts = build_command(phase_config, issue_number)

        # コマンドは最初の要素
        result = [command_parts[0]]

        # オプションが存在する場合（コマンド、オプション、パラメータの3つ以上の要素がある場合）
        if phase_config.options&.any?
          result.concat(phase_config.options)
        end

        # パラメータがある場合はダブルクォートで囲む
        if phase_config.parameter
          parameter = phase_config.parameter.gsub('{{issue-number}}', issue_number.to_s)
          # パラメータにスペースやスラッシュが含まれる場合はダブルクォートで囲む
          if parameter.include?(' ') || parameter.include?('/')
            result << "\"#{parameter}\""
          else
            result << parameter
          end
        end

        result.join(' ')
      end

      def build_command_string_with_worktree(phase_config, issue_number)
        command_string = build_command_string(phase_config, issue_number)
        worktree_path = @git_workspace_manager.get_worktree_path(issue_number)

        if worktree_path
          "cd #{worktree_path} && #{command_string}"
        else
          command_string
        end
      end

      def apply_command_delay
        begin
          config = Soba::Configuration.load!
          delay = config&.workflow&.tmux_command_delay
          delay = 3 if delay.nil?
        rescue StandardError
          delay = 3
        end

        if delay && delay > 0
          sleep(delay)
        end
      end
    end
  end
end