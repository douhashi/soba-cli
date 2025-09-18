# frozen_string_literal: true

require "spec_helper"
require "soba/commands/start"

RSpec.describe Soba::Commands::Start do
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
      expect(command.instance_variable_get(:@configuration)).to be_nil
      expect(command.instance_variable_get(:@issue_processor)).to be_nil
    end

    it "カスタム設定とプロセッサを使用できる" do
      expect(command.instance_variable_get(:@configuration)).to eq(configuration)
      expect(command.instance_variable_get(:@issue_processor)).to eq(issue_processor)
    end
  end

  describe "#execute" do
    before do
      allow(issue_processor).to receive(:run)
      allow(command).to receive(:execute_workflow)
    end

    context "引数がない場合（ワークフロー実行）" do
      let(:global_options) { {} }
      let(:options) { {} }
      let(:args) { [] }

      it "execute_workflowを呼び出す" do
        expect(command).to receive(:execute_workflow).with(global_options, options)
        command.execute(global_options, options, args)
      end
    end

    context "Issue番号が指定された場合（単一Issue実行）" do
      let(:global_options) { {} }
      let(:options) { {} }
      let(:args) { ["21"] }

      it "tmuxを有効にしてIssueを処理する" do
        expect(issue_processor).to receive(:run).with("21", use_tmux: true)
        command.execute(global_options, options, args)
      end

      context "--no-tmuxオプションが指定された場合" do
        let(:options) { { "no-tmux" => true } }

        it "tmuxを無効にしてIssueを処理する" do
          expect(issue_processor).to receive(:run).with("21", use_tmux: false)
          command.execute(global_options, options, args)
        end

        it "直接実行モードのメッセージを表示する" do
          expect { command.execute(global_options, options, args) }.to output(/Running in direct mode/).to_stdout
        end
      end

      context "環境変数SOBA_NO_TMUXが設定された場合" do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("SOBA_NO_TMUX").and_return("true")
        end

        it "tmuxを無効にしてIssueを処理する" do
          expect(issue_processor).to receive(:run).with("21", use_tmux: false)
          command.execute(global_options, options, args)
        end

        it "環境変数による設定メッセージを表示する" do
          expect { command.execute(global_options, options, args) }.to output(/tmux disabled by environment variable/).to_stdout
        end
      end

      context "設定ファイルでuse_tmux: falseの場合" do
        let(:workflow_config) { double("workflow", use_tmux: false) }

        it "tmuxを無効にしてIssueを処理する" do
          expect(issue_processor).to receive(:run).with("21", use_tmux: false)
          command.execute(global_options, options, args)
        end
      end

      context "エラーハンドリング" do
        it "IssueProcessor実行時のエラーをキャッチする" do
          allow(issue_processor).to receive(:run).and_raise(StandardError.new("Processing failed"))
          allow(command).to receive(:warn)
          result = command.execute(global_options, options, args)
          expect(command).to have_received(:warn).with("Error: Processing failed")
          expect(result).to eq(1)
        end
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