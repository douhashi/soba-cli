# frozen_string_literal: true

require "spec_helper"
require "soba/commands/monitor"

RSpec.describe Soba::Commands::Monitor do
  let(:session_monitor) { instance_double(Soba::Services::SessionMonitor) }
  let(:command) { described_class.new(monitor: session_monitor) }

  describe "#initialize" do
    it "SessionMonitorインスタンスを生成する" do
      command = described_class.new
      expect(command.instance_variable_get(:@monitor)).to be_a(Soba::Services::SessionMonitor)
    end

    it "カスタムモニターを使用できる" do
      expect(command.instance_variable_get(:@monitor)).to eq(session_monitor)
    end
  end

  describe "#execute" do
    context "引数なしの場合" do
      it "アクティブセッション一覧を表示する" do
        allow(session_monitor).to receive(:list_sessions).and_return({
          active: ["soba-21", "soba-22"],
          with_logs: ["soba-19", "soba-20", "soba-21"],
        })

        expect { command.execute([]) }.to output(/Active sessions/).to_stdout
        expect { command.execute([]) }.to output(/soba-21/).to_stdout
        expect { command.execute([]) }.to output(/soba-22/).to_stdout
      end

      it "ログがあるセッションにマークを付ける" do
        allow(session_monitor).to receive(:list_sessions).and_return({
          active: ["soba-21"],
          with_logs: ["soba-21"],
        })

        expect { command.execute([]) }.to output(/soba-21 \[log\]/).to_stdout
      end
    end

    context "セッション番号が指定された場合" do
      it "セッション監視を開始する" do
        expect(session_monitor).to receive(:attach).with("soba-21", follow_log: false)

        command.execute(["21"])
      end

      it "セッション名でも監視できる" do
        expect(session_monitor).to receive(:attach).with("soba-custom", follow_log: false)

        command.execute(["soba-custom"])
      end
    end

    context "--follow-logオプション" do
      it "既存ログのみをフォローする" do
        expect(session_monitor).to receive(:attach).with("soba-21", follow_log: true)

        command.execute(["21", "--follow-log"])
      end
    end

    context "--listオプション" do
      it "セッション一覧を表示する" do
        allow(session_monitor).to receive(:list_sessions).and_return({
          active: ["soba-21"],
          with_logs: ["soba-19", "soba-20"],
        })

        expect { command.execute(["--list"]) }.to output(/Sessions with logs/).to_stdout
        expect { command.execute(["--list"]) }.to output(/soba-19/).to_stdout
        expect { command.execute(["--list"]) }.to output(/soba-20/).to_stdout
      end
    end

    context "--cleanupオプション" do
      it "古いログをクリーンアップする" do
        logger = instance_double(Soba::Services::SessionLogger)
        allow(session_monitor).to receive(:logger).and_return(logger)
        expect(logger).to receive(:cleanup_old_logs).with(days: 30)

        expect { command.execute(["--cleanup"]) }.to output(/Cleaned up logs older than 30 days/).to_stdout
      end

      it "カスタム日数を指定できる" do
        logger = instance_double(Soba::Services::SessionLogger)
        allow(session_monitor).to receive(:logger).and_return(logger)
        expect(logger).to receive(:cleanup_old_logs).with(days: 7)

        expect { command.execute(["--cleanup", "7"]) }.to output(/Cleaned up logs older than 7 days/).to_stdout
      end
    end

    context "エラーハンドリング" do
      it "セッションが見つからない場合のエラーメッセージ" do
        allow(session_monitor).to receive(:attach).and_raise(
          Soba::Services::SessionMonitor::SessionNotFoundError.new("Session 'soba-99' not found")
        )

        expect { command.execute(["99"]) }.to output(/Session 'soba-99' not found/).to_stderr
      end

      it "割り込み時のメッセージ" do
        allow(session_monitor).to receive(:attach).and_raise(Interrupt)

        expect { command.execute(["21"]) }.to output(/Monitoring stopped/).to_stdout
      end
    end
  end

  describe "#parse_session_name" do
    it "数値をセッション名に変換する" do
      result = command.send(:parse_session_name, "21")
      expect(result).to eq("soba-21")
    end

    it "既存のセッション名はそのまま返す" do
      result = command.send(:parse_session_name, "soba-custom")
      expect(result).to eq("soba-custom")
    end

    it "プレフィックス付き番号も処理する" do
      result = command.send(:parse_session_name, "soba-42")
      expect(result).to eq("soba-42")
    end
  end

  describe "#format_session_list" do
    it "アクティブセッションとログセッションを整形する" do
      sessions = {
        active: ["soba-21", "soba-22"],
        with_logs: ["soba-20", "soba-21"],
      }

      output = command.send(:format_session_list, sessions)

      expect(output).to include("Active sessions:")
      expect(output).to include("  - soba-21 [log]")
      expect(output).to include("  - soba-22")
      expect(output).to include("Sessions with logs:")
      expect(output).to include("  - soba-20")
    end
  end
end