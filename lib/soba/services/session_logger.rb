# frozen_string_literal: true

require "fileutils"
require "time"

module Soba
  module Services
    # セッション出力のログ管理サービス
    class SessionLogger
      DEFAULT_LOG_DIR = File.join(Dir.home, ".soba", "logs")
      DEFAULT_MAX_SIZE = 10 * 1024 * 1024 # 10MB

      attr_reader :log_dir

      def initialize(log_dir: nil, max_size: DEFAULT_MAX_SIZE)
        @log_dir = log_dir || DEFAULT_LOG_DIR
        @max_size = max_size
        @file_handles = {}

        ensure_log_directory
      end

      # ログファイルに書き込み
      def write(session_name, content)
        ensure_file_handle(session_name)

        timestamp = Time.now.strftime("[%Y-%m-%d %H:%M:%S]")
        @file_handles[session_name].write("#{timestamp} #{content}")
        @file_handles[session_name].flush

        # ローテーションチェック
        check_rotation(session_name)
      end

      # セッションのログファイルパスを取得
      def find_log(session_name)
        log_file = File.join(@log_dir, "#{session_name}.log")
        File.exist?(log_file) ? log_file : nil
      end

      # ログが存在するセッション一覧
      def list_sessions
        Dir.glob(File.join(@log_dir, "soba-*.log")).
          reject { |f| f.include?(".log.") }. # ローテートファイルを除外
          map { |f| File.basename(f, ".log") }.
          sort
      end

      # ファイルハンドルをクローズ
      def close
        @file_handles.each_value(&:close)
        @file_handles.clear
      end

      # 古いログファイルのクリーンアップ
      def cleanup_old_logs(days: 30)
        cutoff_time = Time.now - (days * 24 * 60 * 60)

        Dir.glob(File.join(@log_dir, "soba-*.log*")).each do |file|
          if File.mtime(file) < cutoff_time
            File.delete(file)
          end
        end
      end

      private

      # ログディレクトリの確認と作成
      def ensure_log_directory
        FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
      end

      # ファイルハンドルの取得または作成
      def ensure_file_handle(session_name)
        return if @file_handles[session_name]

        log_file = File.join(@log_dir, "#{session_name}.log")
        @file_handles[session_name] = File.open(log_file, "a")
      end

      # ログローテーションのチェック
      def check_rotation(session_name)
        log_file = File.join(@log_dir, "#{session_name}.log")
        return unless File.size(log_file) > @max_size

        rotate_log(session_name)
      end

      # ログファイルのローテート
      def rotate_log(session_name)
        log_file = File.join(@log_dir, "#{session_name}.log")

        # ファイルハンドルを閉じる
        @file_handles[session_name]&.close
        @file_handles.delete(session_name)

        # ローテート番号を決定
        rotate_number = 1
        while File.exist?("#{log_file}.#{rotate_number}")
          rotate_number += 1
        end

        # ファイルを移動
        File.rename(log_file, "#{log_file}.#{rotate_number}")

        # 新しいファイルハンドルを開く
        ensure_file_handle(session_name)
      end
    end
  end
end