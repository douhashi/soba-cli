# frozen_string_literal: true

require "spec_helper"
require "soba/services/session_monitor"

RSpec.describe Soba::Services::SessionMonitor do
  let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
  let(:session_logger) { instance_double(Soba::Services::SessionLogger) }
  let(:ansi_processor) { instance_double(Soba::Services::AnsiProcessor) }
  let(:monitor) { described_class.new(tmux_client: tmux_client, logger: session_logger, ansi_processor: ansi_processor) }

  describe "#initialize" do
    it "初期化パラメータを正しく設定する" do
      expect(monitor.instance_variable_get(:@tmux_client)).to eq(tmux_client)
      expect(monitor.instance_variable_get(:@logger)).to eq(session_logger)
      expect(monitor.instance_variable_get(:@ansi_processor)).to eq(ansi_processor)
    end

    context "依存関係がnilの場合" do
      it "デフォルトのインスタンスを生成する" do
        monitor = described_class.new
        expect(monitor.instance_variable_get(:@tmux_client)).to be_a(Soba::Infrastructure::TmuxClient)
        expect(monitor.instance_variable_get(:@logger)).to be_a(Soba::Services::SessionLogger)
        expect(monitor.instance_variable_get(:@ansi_processor)).to be_a(Soba::Services::AnsiProcessor)
      end
    end
  end

  describe "#start" do
    let(:session_name) { "soba-21" }
    let(:pane_id) { "%5" }
    let(:output_text) { "test output" }
    let(:processed_text) { "processed output" }

    before do
      allow(tmux_client).to receive(:find_pane).with(session_name).and_return(pane_id)
      allow(tmux_client).to receive(:capture_pane_continuous).with(pane_id).and_yield(output_text)
      allow(ansi_processor).to receive(:process).with(output_text).and_return(processed_text)
      allow(session_logger).to receive(:write)
      allow(monitor).to receive(:display_output)
    end

    it "指定セッションの監視を開始する" do
      expect(tmux_client).to receive(:find_pane).with(session_name).and_return(pane_id)
      expect(tmux_client).to receive(:capture_pane_continuous).with(pane_id)

      monitor.start(session_name)
    end

    it "キャプチャした出力を処理・記録・表示する" do
      expect(ansi_processor).to receive(:process).with(output_text).and_return(processed_text)
      expect(session_logger).to receive(:write).with(session_name, processed_text)
      expect(monitor).to receive(:display_output).with(processed_text)

      monitor.start(session_name)
    end

    context "セッションが見つからない場合" do
      before do
        allow(tmux_client).to receive(:find_pane).with(session_name).and_return(nil)
      end

      it "エラーをraiseする" do
        expect { monitor.start(session_name) }.to raise_error(Soba::Services::SessionMonitor::SessionNotFoundError, "Session 'soba-21' not found")
      end
    end

    context "割り込み発生時" do
      before do
        allow(tmux_client).to receive(:capture_pane_continuous).and_raise(Interrupt)
      end

      it "gracefulにシャットダウンする" do
        expect(session_logger).to receive(:close)
        expect { monitor.start(session_name) }.to output(/Monitoring stopped/).to_stdout
      end
    end
  end

  describe "#stop" do
    it "監視を停止する" do
      allow(session_logger).to receive(:close)
      monitor.instance_variable_set(:@running, true)
      monitor.stop
      expect(monitor.instance_variable_get(:@running)).to be(false)
    end

    it "ロガーを閉じる" do
      expect(session_logger).to receive(:close)
      monitor.stop
    end
  end

  describe "#display_output" do
    let(:output_text) { "test output\nline 2" }

    it "標準出力に表示する" do
      expect { monitor.send(:display_output, output_text) }.to output("test output\nline 2").to_stdout
    end

    context "リアルタイム出力モードが無効の場合" do
      let(:monitor) { described_class.new(tmux_client: tmux_client, logger: session_logger, ansi_processor: ansi_processor, realtime: false) }

      it "出力しない" do
        expect { monitor.send(:display_output, output_text) }.not_to output.to_stdout
      end
    end
  end

  describe "#attach" do
    let(:session_name) { "soba-21" }
    let(:log_file) { "/tmp/soba/logs/soba-21.log" }

    before do
      allow(session_logger).to receive(:find_log).with(session_name).and_return(log_file)
      allow(File).to receive(:exist?).with(log_file).and_return(true)
    end

    context "既存のログファイルがある場合" do
      it "tail -fで既存ログを表示する" do
        expect(monitor).to receive(:system).with("tail -f #{log_file}")
        monitor.attach(session_name)
      end
    end

    context "ログファイルが存在しない場合" do
      before do
        allow(File).to receive(:exist?).with(log_file).and_return(false)
      end

      it "新規監視を開始する" do
        expect(monitor).to receive(:start).with(session_name)
        monitor.attach(session_name)
      end
    end

    context "follow_logオプションが指定された場合" do
      it "tail -fで既存ログのみ表示する" do
        expect(monitor).to receive(:system).with("tail -f #{log_file}")
        expect(monitor).not_to receive(:start)
        monitor.attach(session_name, follow_log: true)
      end
    end
  end

  describe "#list_sessions" do
    let(:active_sessions) { ["soba-21", "soba-22"] }
    let(:log_sessions) { ["soba-19", "soba-20", "soba-21"] }

    before do
      allow(tmux_client).to receive(:list_soba_sessions).and_return(active_sessions)
      allow(session_logger).to receive(:list_sessions).and_return(log_sessions)
    end

    it "アクティブセッションとログセッションのリストを返す" do
      result = monitor.list_sessions
      expect(result[:active]).to eq(active_sessions)
      expect(result[:with_logs]).to eq(log_sessions)
    end
  end
end