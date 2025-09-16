# frozen_string_literal: true

require "spec_helper"
require "soba/services/session_monitor"
require "soba/services/session_logger"
require "soba/services/ansi_processor"
require "soba/infrastructure/tmux_client"
require "soba/commands/monitor"
require "tmpdir"

RSpec.describe "Monitor Integration", :integration do
  let(:tmux_client) { Soba::Infrastructure::TmuxClient.new }
  let(:test_session) { "soba-test-#{Process.pid}" }
  let(:test_log_dir) { Dir.mktmpdir("soba-monitor-test") }

  after do
    # クリーンアップ
    tmux_client.kill_session(test_session) if tmux_client.session_exists?(test_session)
    FileUtils.rm_rf(test_log_dir) if Dir.exist?(test_log_dir)
  end

  describe "セッション監視機能の統合テスト" do
    it "tmuxセッションの出力をキャプチャしてログに保存する" do
      # テストセッションを作成
      expect(tmux_client.create_session(test_session)).to be(true)

      # モニター設定
      logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)
      ansi_processor = Soba::Services::AnsiProcessor.new
      monitor = Soba::Services::SessionMonitor.new(
        tmux_client: tmux_client,
        logger: logger,
        ansi_processor: ansi_processor,
        realtime: false
      )

      # 監視を非同期で開始
      thread = Thread.new do
        monitor.start(test_session)
      rescue Soba::Services::SessionMonitor::SessionNotFoundError
        # Expected when session is killed
      end

      # 監視が開始されるのを待つ
      sleep 1

      # セッションにコマンドを送信
      tmux_client.send_keys(test_session, "echo 'Test output'")
      sleep 2

      # 監視を停止
      monitor.stop
      thread.kill
      thread.join(1) # スレッドの終了を待つ

      # ログファイルを確認
      log_file = File.join(test_log_dir, "#{test_session}.log")
      expect(File.exist?(log_file)).to be(true)

      log_content = File.read(log_file)

      # 最低限、コマンドの出力が記録されていることを確認
      expect(log_content).to include("Test output")
    end

    it "ANSIカラーコードを処理する" do
      # テストセッションを作成
      expect(tmux_client.create_session(test_session)).to be(true)

      # カラー出力を送信
      tmux_client.send_keys(test_session, "echo -e '\\033[31mRed text\\033[0m'")
      sleep 0.5

      # モニター設定（ANSIコード削除）
      logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)
      ansi_processor = Soba::Services::AnsiProcessor.new(strip_codes: true)
      monitor = Soba::Services::SessionMonitor.new(
        tmux_client: tmux_client,
        logger: logger,
        ansi_processor: ansi_processor,
        realtime: false
      )

      # 監視を短時間実行
      thread = Thread.new { monitor.start(test_session) }
      sleep 1
      monitor.stop
      thread.kill

      # ログファイルを確認
      log_file = File.join(test_log_dir, "#{test_session}.log")
      log_content = File.read(log_file)

      # ANSIコードが削除されていることを確認
      expect(log_content).not_to include("\033[31m")
      expect(log_content).to include("Red text")
    end

    it "既存のログファイルにアタッチできる" do
      # ログファイルを事前に作成
      log_file = File.join(test_log_dir, "#{test_session}.log")
      File.write(log_file, "Previous session output\n")

      logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)

      # find_logメソッドが正しくファイルを見つけることを確認
      expect(logger.find_log(test_session)).to eq(log_file)
    end

    it "複数のセッションを同時に監視できる" do
      session1 = "#{test_session}-1"
      session2 = "#{test_session}-2"

      # 複数のセッションを作成
      expect(tmux_client.create_session(session1)).to be(true)
      expect(tmux_client.create_session(session2)).to be(true)

      begin
        # それぞれにコマンドを送信
        tmux_client.send_keys(session1, "echo 'Session 1'")
        tmux_client.send_keys(session2, "echo 'Session 2'")
        sleep 0.5

        # 両方のセッションを監視
        logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)
        ansi_processor = Soba::Services::AnsiProcessor.new
        monitor1 = Soba::Services::SessionMonitor.new(
          tmux_client: tmux_client,
          logger: logger,
          ansi_processor: ansi_processor,
          realtime: false
        )
        monitor2 = Soba::Services::SessionMonitor.new(
          tmux_client: tmux_client,
          logger: logger,
          ansi_processor: ansi_processor,
          realtime: false
        )

        threads = []
        threads << Thread.new { monitor1.start(session1) }
        threads << Thread.new { monitor2.start(session2) }

        sleep 1

        # 監視を停止
        monitor1.stop
        monitor2.stop
        threads.each(&:kill)

        # 両方のログファイルを確認
        log1 = File.read(File.join(test_log_dir, "#{session1}.log"))
        log2 = File.read(File.join(test_log_dir, "#{session2}.log"))

        expect(log1).to include("Session 1")
        expect(log2).to include("Session 2")
      ensure
        tmux_client.kill_session(session1)
        tmux_client.kill_session(session2)
      end
    end
  end

  describe "Monitorコマンドの統合テスト" do
    it "コマンド経由でセッション一覧を表示できる" do
      # テストセッションを作成
      expect(tmux_client.create_session(test_session)).to be(true)

      # ログファイルも作成
      logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)
      logger.write(test_session, "test log")
      logger.close

      # モニターコマンドを実行
      monitor_service = Soba::Services::SessionMonitor.new(
        tmux_client: tmux_client,
        logger: logger
      )
      command = Soba::Commands::Monitor.new(monitor: monitor_service)

      output = capture_stdout { command.execute([]) }

      expect(output).to include("Active sessions:")
      expect(output).to include(test_session)
      expect(output).to include("[log]")
    end

    it "古いログをクリーンアップできる" do
      # 古いログファイルを作成
      old_log = File.join(test_log_dir, "soba-old.log")
      FileUtils.touch(old_log)

      # ファイルの更新時刻を31日前に設定
      old_time = Time.now - (31 * 24 * 60 * 60)
      File.utime(old_time, old_time, old_log)

      # 新しいログファイルも作成
      new_log = File.join(test_log_dir, "soba-new.log")
      FileUtils.touch(new_log)

      # クリーンアップを実行
      logger = Soba::Services::SessionLogger.new(log_dir: test_log_dir)
      monitor = Soba::Services::SessionMonitor.new(logger: logger)
      command = Soba::Commands::Monitor.new(monitor: monitor)

      output = capture_stdout { command.execute(["--cleanup", "30"]) }

      expect(output).to include("Cleaned up logs older than 30 days")
      expect(File.exist?(old_log)).to be(false)
      expect(File.exist?(new_log)).to be(true)
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end