# frozen_string_literal: true

require "spec_helper"
require "soba/commands/workflow/run"

RSpec.describe Soba::Commands::Workflow::Run do
  let(:workflow_config) { double("workflow", use_tmux: true) }
  let(:github_config) { double("github", repository: "owner/repo") }
  let(:config_object) { double("config", workflow: workflow_config, github: github_config) }
  let(:configuration) { class_double(Soba::Configuration, config: config_object, load!: config_object) }
  let(:issue_processor) { instance_double(Soba::Services::IssueProcessor) }
  let(:command) { described_class.new(configuration: configuration, issue_processor: issue_processor) }

  before do
    allow(Soba::Configuration).to receive(:load!).and_return(configuration)
  end

  describe "#initialize" do
    it "設定とIssueProcessorインスタンスを初期化する" do
      command = described_class.new
      expect(command.instance_variable_get(:@configuration)).not_to be_nil
      expect(command.instance_variable_get(:@issue_processor)).to be_a(Soba::Services::IssueProcessor)
    end

    it "カスタム設定とプロセッサを使用できる" do
      expect(command.instance_variable_get(:@configuration)).to eq(configuration)
      expect(command.instance_variable_get(:@issue_processor)).to eq(issue_processor)
    end
  end

  describe "#execute" do
    let(:args) { ["21"] }
    let(:options) { {} }

    before do
      allow(issue_processor).to receive(:run)
    end

    context "デフォルト動作" do
      it "tmuxを有効にしてIssueを処理する" do
        expect(issue_processor).to receive(:run).with("21", use_tmux: true)
        command.execute(args, options)
      end
    end

    context "--no-tmuxオプションが指定された場合" do
      let(:options) { { "no-tmux" => true } }

      it "tmuxを無効にしてIssueを処理する" do
        expect(issue_processor).to receive(:run).with("21", use_tmux: false)
        command.execute(args, options)
      end

      it "直接実行モードのメッセージを表示する" do
        expect { command.execute(args, options) }.to output(/Running in direct mode/).to_stdout
      end
    end

    context "環境変数SOBA_NO_TMUXが設定された場合" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("true")
      end

      it "tmuxを無効にしてIssueを処理する" do
        expect(issue_processor).to receive(:run).with("21", use_tmux: false)
        command.execute(args, options)
      end

      it "環境変数による設定メッセージを表示する" do
        expect { command.execute(args, options) }.to output(/tmux disabled by environment variable/).to_stdout
      end
    end

    context "設定ファイルでuse_tmux: falseの場合" do
      let(:workflow_config) { double("workflow", use_tmux: false) }

      it "tmuxを無効にしてIssueを処理する" do
        expect(issue_processor).to receive(:run).with("21", use_tmux: false)
        command.execute(args, options)
      end
    end

    context "優先順位のテスト" do
      context "CLIオプション > 環境変数" do
        let(:options) { { "no-tmux" => true } }

        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("false")
        end

        it "CLIオプションを優先する" do
          expect(issue_processor).to receive(:run).with("21", use_tmux: false)
          command.execute(args, options)
        end
      end

      context "環境変数 > 設定ファイル" do
        let(:workflow_config) { double("workflow", use_tmux: false) }

        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("false")
        end

        it "環境変数を優先してtmuxを有効にする" do
          expect(issue_processor).to receive(:run).with("21", use_tmux: true)
          command.execute(args, options)
        end
      end
    end

    context "環境変数の値のバリエーション" do
      it "SOBA_NO_TMUX=1でtmuxを無効化" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("1")

        expect(issue_processor).to receive(:run).with("21", use_tmux: false)
        command.execute(args, options)
      end

      it "SOBA_NO_TMUX=falseでtmuxを有効化" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("false")

        expect(issue_processor).to receive(:run).with("21", use_tmux: true)
        command.execute(args, options)
      end

      it "SOBA_NO_TMUX=0でtmuxを有効化" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("0")

        expect(issue_processor).to receive(:run).with("21", use_tmux: true)
        command.execute(args, options)
      end
    end

    context "tmuxモードの表示" do
      it "tmux有効時にメッセージを表示する" do
        expect { command.execute(args, options) }.to output(/Running issue #21 with tmux/).to_stdout
      end

      context "--no-tmuxオプション使用時" do
        let(:options) { { "no-tmux" => true } }

        it "直接実行モードのメッセージを表示する" do
          expect { command.execute(args, options) }.to output(/Running in direct mode \(tmux disabled\)/).to_stdout
        end
      end
    end

    context "エラーハンドリング" do
      it "Issue番号が指定されない場合のエラー" do
        allow(STDERR).to receive(:puts)
        result = command.execute([], options)
        expect(STDERR).to have_received(:puts).with("Error: Issue number is required")
        expect(result).to eq(1)
      end

      it "IssueProcessor実行時のエラーをキャッチする" do
        allow(issue_processor).to receive(:run).and_raise(StandardError.new("Processing failed"))
        allow(STDERR).to receive(:puts)
        result = command.execute(args, options)
        expect(STDERR).to have_received(:puts).with("Error: Processing failed")
        expect(result).to eq(1)
      end
    end
  end

  describe "#determine_tmux_mode" do
    let(:options) { {} }

    it "デフォルトは設定ファイルの値を使用" do
      result = command.send(:determine_tmux_mode, options)
      expect(result).to eq(true)
    end

    it "CLIオプションを最優先" do
      options["no-tmux"] = true
      result = command.send(:determine_tmux_mode, options)
      expect(result).to eq(false)
    end

    it "環境変数を設定より優先" do
      allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("true")
      result = command.send(:determine_tmux_mode, options)
      expect(result).to eq(false)
    end
  end
end