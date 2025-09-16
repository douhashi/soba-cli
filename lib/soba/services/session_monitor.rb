# frozen_string_literal: true

require "concurrent"
require_relative "../infrastructure/tmux_client"
require_relative "session_logger"
require_relative "ansi_processor"

module Soba
  module Services
    # セッション出力のリアルタイム監視サービス
    class SessionMonitor
      class SessionNotFoundError < StandardError; end

      attr_reader :tmux_client, :logger, :ansi_processor

      def initialize(tmux_client: nil, logger: nil, ansi_processor: nil, realtime: true)
        @tmux_client = tmux_client || Infrastructure::TmuxClient.new
        @logger = logger || SessionLogger.new
        @ansi_processor = ansi_processor || AnsiProcessor.new
        @realtime = realtime
        @running = false
      end

      # 指定セッションの監視を開始
      def start(session_name)
        pane_id = @tmux_client.find_pane(session_name)
        raise SessionNotFoundError, "Session '#{session_name}' not found" unless pane_id

        @running = true
        monitor_pane(session_name, pane_id)
      rescue Interrupt
        puts "\nMonitoring stopped"
        stop
      end

      # 監視を停止
      def stop
        @running = false
        @logger.close
      end

      # 既存セッションにアタッチ（ログまたは新規監視）
      def attach(session_name, follow_log: false)
        log_file = @logger.find_log(session_name)

        if log_file && File.exist?(log_file)
          # 既存ログをtail -fで表示
          system("tail -f #{log_file}")
        elsif !follow_log
          # 新規監視を開始
          start(session_name)
        else
          puts "No log file found for session '#{session_name}'"
        end
      end

      # アクティブセッションとログのリスト表示
      def list_sessions
        active = @tmux_client.list_soba_sessions
        with_logs = @logger.list_sessions

        {
          active: active,
          with_logs: with_logs,
        }
      end

      private

      # ペインの継続的監視
      def monitor_pane(session_name, pane_id)
        @tmux_client.capture_pane_continuous(pane_id) do |output|
          break unless @running

          processed = @ansi_processor.process(output)
          @logger.write(session_name, processed)
          display_output(processed)
        end
      end

      # リアルタイム出力表示
      def display_output(output)
        return unless @realtime

        print output
        $stdout.flush
      end
    end
  end
end