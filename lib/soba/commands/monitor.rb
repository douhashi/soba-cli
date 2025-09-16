# frozen_string_literal: true

require_relative "../services/session_monitor"

module Soba
  module Commands
    # セッション監視コマンド
    class Monitor
      def initialize(monitor: nil)
        @monitor = monitor || Services::SessionMonitor.new
      end

      def execute(args)
        if args.empty?
          show_session_list
        elsif args.include?("--list")
          show_detailed_list
        elsif args.include?("--cleanup")
          cleanup_logs(args)
        else
          monitor_session(args)
        end
      rescue Services::SessionMonitor::SessionNotFoundError => e
        warn e.message
        exit 1
      rescue Interrupt
        puts "\nMonitoring stopped"
      end

      private

      # セッション一覧を表示
      def show_session_list
        sessions = @monitor.list_sessions
        puts format_session_list(sessions)
      end

      # 詳細なセッション一覧を表示
      def show_detailed_list
        sessions = @monitor.list_sessions

        puts "Active sessions:"
        sessions[:active].each do |session|
          puts "  - #{session}"
        end

        puts "\nSessions with logs:"
        sessions[:with_logs].each do |session|
          puts "  - #{session}"
        end
      end

      # セッション監視を開始
      def monitor_session(args)
        session_name = parse_session_name(args[0])
        follow_log = args.include?("--follow-log")

        @monitor.attach(session_name, follow_log: follow_log)
      end

      # 古いログをクリーンアップ
      def cleanup_logs(args)
        days = 30

        # --cleanupの後に数値があればそれを日数として使用
        cleanup_index = args.index("--cleanup")
        if cleanup_index && args[cleanup_index + 1]&.match?(/^\d+$/)
          days = args[cleanup_index + 1].to_i
        end

        @monitor.logger.cleanup_old_logs(days: days)
        puts "Cleaned up logs older than #{days} days"
      end

      # セッション名をパース
      def parse_session_name(input)
        # 数値のみの場合はsoba-プレフィックスを付ける
        if input.match?(/^\d+$/)
          "soba-#{input}"
        else
          input
        end
      end

      # セッション一覧を整形
      def format_session_list(sessions)
        output = []

        output << "Active sessions:"
        sessions[:active].each do |session|
          log_marker = sessions[:with_logs].include?(session) ? " [log]" : ""
          output << "  - #{session}#{log_marker}"
        end

        if sessions[:active].empty?
          output << "  (none)"
        end

        output << "\nSessions with logs:"
        log_only = sessions[:with_logs] - sessions[:active]
        log_only.each do |session|
          output << "  - #{session}"
        end

        if log_only.empty?
          output << "  (none)"
        end

        output.join("\n")
      end
    end
  end
end