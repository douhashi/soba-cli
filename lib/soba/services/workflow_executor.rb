# frozen_string_literal: true

require 'open3'

module Soba
  module Services
    class WorkflowExecutionError < StandardError; end

    class WorkflowExecutor
      def initialize(tmux_session_manager: nil)
        @tmux_session_manager = tmux_session_manager
      end

      def execute(phase:, issue_number:, use_tmux: true)
        return nil unless phase.command

        if use_tmux
          execute_in_tmux(phase: phase, issue_number: issue_number)
        else
          execute_direct(phase: phase, issue_number: issue_number)
        end
      end

      def execute_direct(phase:, issue_number:)
        return nil unless phase.command

        command_array = build_command(phase, issue_number)

        stdout, stderr, status = Open3.popen3(*command_array) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          [stdout.read, stderr.read, wait_thr.value]
        end

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

        command_string = build_command_string(phase, issue_number)

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
            tmux_client = Soba::Infrastructure::TmuxClient.new
            tmux_client.send_keys("#{session_result[:session_name]}:#{window_result[:window_name]}", command_string)
            pane_id = nil
          else
            # 既存windowの場合は新規paneを作成
            pane_result = @tmux_session_manager.create_phase_pane(
              session_name: session_result[:session_name],
              window_name: window_result[:window_name],
              phase: phase.name
            )
            return pane_result unless pane_result[:success]

            pane_id = pane_result[:pane_id]
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
        build_command(phase_config, issue_number).join(' ')
      end
    end
  end
end