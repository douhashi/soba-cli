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

      context "デフォルト（フォアグラウンド実行）" do
        it "フォアグラウンドで実行される" do
          expect(command).to receive(:execute_workflow).with(global_options, options)
          command.execute(global_options, options, args)
        end
      end

      context "--daemonオプションが指定された場合" do
        let(:options) { { daemon: true } }

        it "デーモンモードで実行される" do
          expect(command).to receive(:execute_workflow).with(global_options, options)
          command.execute(global_options, options, args)
        end
      end

      context "--foregroundオプションが指定された場合（廃止予定）" do
        let(:options) { { foreground: true } }

        it "廃止予定の警告を表示する" do
          expect { command.execute(global_options, options, args) }.to output(/DEPRECATED/).to_stdout
        end

        it "フォアグラウンドで実行される（互換性のため）" do
          allow(command).to receive(:puts)
          expect(command).to receive(:execute_workflow).with(global_options, hash_excluding(:foreground))
          command.execute(global_options, options, args)
        end
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

  describe "#execute_workflow" do
    let(:global_options) { {} }
    let(:options) { {} } # デフォルトはフォアグラウンド
    let(:tmux_session_manager) { instance_double(Soba::Services::TmuxSessionManager) }
    let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
    let(:tmux_client) { instance_double(Soba::Infrastructure::TmuxClient) }
    let(:workflow_config) { double("workflow", use_tmux: true, interval: 10, auto_merge_enabled: false, closed_issue_cleanup_enabled: false) }
    let(:github_config) { double("github", repository: "owner/repo") }
    let(:config_object) { double("config", workflow: workflow_config, github: github_config) }

    before do
      # Ensure configuration is properly loaded
      allow(Soba::Configuration).to receive(:load!).and_return(config_object)
      allow(Soba::Configuration).to receive(:config).and_return(config_object)

      allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
      allow(Soba::Infrastructure::TmuxClient).to receive(:new).and_return(tmux_client)
      allow(Soba::Services::TmuxSessionManager).to receive(:new).and_return(tmux_session_manager)

      # Stub all other dependencies
      allow(Soba::Services::WorkflowExecutor).to receive(:new).and_return(instance_double(Soba::Services::WorkflowExecutor))
      allow(Soba::Domain::PhaseStrategy).to receive(:new).and_return(instance_double(Soba::Domain::PhaseStrategy))
      allow(Soba::Services::IssueProcessor).to receive(:new).and_return(instance_double(Soba::Services::IssueProcessor))
      allow(Soba::Services::WorkflowBlockingChecker).to receive(:new).and_return(instance_double(Soba::Services::WorkflowBlockingChecker))
      allow(Soba::Services::QueueingService).to receive(:new).and_return(instance_double(Soba::Services::QueueingService))
      allow(Soba::Services::AutoMergeService).to receive(:new).and_return(instance_double(Soba::Services::AutoMergeService))
      allow(Soba::Services::ClosedIssueWindowCleaner).to receive(:new).and_return(instance_double(Soba::Services::ClosedIssueWindowCleaner, should_clean?: false))
      allow(Soba::Services::StatusManager).to receive(:new).and_return(instance_double(Soba::Services::StatusManager, update_memory: nil, update_current_issue: nil, update_last_processed: nil))
      allow(Soba::Services::IssueWatcher).to receive(:new).and_return(instance_double(Soba::Services::IssueWatcher, fetch_issues: []))

      # Stop infinite loop
      allow(command).to receive(:puts)
    end

    context "デフォルト（フォアグラウンドモード）" do
      it "ワークフロー開始時に空のtmuxセッションを作成する" do
        # Expect tmux session to be created
        expect(tmux_session_manager).to receive(:find_or_create_repository_session).once.and_return({
          success: true,
          session_name: 'soba-owner-repo',
          created: true,
        })

        # Mock sleep to prevent waiting
        allow(command).to receive(:sleep) { command.instance_variable_set(:@running, false) }

        command.send(:execute_workflow, global_options, options)
      end

      it "デーモン化されない" do
        expect(Soba::Services::DaemonService).not_to receive(:new)
        allow(tmux_session_manager).to receive(:find_or_create_repository_session).and_return({
          success: true,
          session_name: 'soba-owner-repo',
          created: false,
        })
        allow(command).to receive(:sleep) { command.instance_variable_set(:@running, false) }
        command.send(:execute_workflow, global_options, options)
      end
    end

    context "--daemonオプションが指定された場合" do
      let(:options) { { daemon: true } }
      let(:pid_manager) { instance_double(Soba::Services::PidManager) }
      let(:daemon_service) { instance_double(Soba::Services::DaemonService) }

      before do
        allow(Soba::Services::PidManager).to receive(:new).and_return(pid_manager)
        allow(Soba::Services::DaemonService).to receive(:new).and_return(daemon_service)
        allow(daemon_service).to receive(:already_running?).and_return(false)
        allow(daemon_service).to receive(:daemonize!)
        allow(daemon_service).to receive(:log)
        allow(daemon_service).to receive(:setup_signal_handlers)

        # Add tmux_session_manager mock
        allow(tmux_session_manager).to receive(:find_or_create_repository_session).and_return({
          success: true,
          session_name: 'soba-owner-repo',
          created: false,
        })
      end

      it "デーモン化される" do
        expect(daemon_service).to receive(:daemonize!)
        allow(command).to receive(:sleep) { command.instance_variable_set(:@running, false) }
        command.send(:execute_workflow, global_options, options)
      end

      it "ログファイルに出力される" do
        expect(daemon_service).to receive(:log).with(/Daemon started successfully/)
        allow(command).to receive(:sleep) { command.instance_variable_set(:@running, false) }
        command.send(:execute_workflow, global_options, options)
      end
    end
  end
end