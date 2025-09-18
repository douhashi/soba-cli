# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "CLI", type: :e2e do
  let(:soba_bin) { File.expand_path("../../bin/soba", __dir__) }

  describe "soba --version" do
    it "displays version" do
      output, status = Open3.capture2("#{soba_bin} --version")
      expect(status).to be_success
      expect(output).to include(Soba::VERSION)
    end
  end

  describe "soba --help" do
    it "displays help message" do
      output, status = Open3.capture2("#{soba_bin} --help")
      expect(status).to be_success
      expect(output).to include("GitHub Issue to Claude Code workflow automation")
      expect(output).to include("issue")
      expect(output).to include("config")
    end
  end

  describe "soba config" do
    it "shows configuration" do
      # テスト用の設定ファイルを作成
      config_content = <<~YAML
        github:
          token: test_token_123
          repository: test/repo
        workflow:
          interval: 30
      YAML

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('.soba')
          File.write('.soba/config.yml', config_content)

          output, status = Open3.capture2("#{soba_bin} config")
          expect(status).to be_success
          expect(output).to include("soba Configuration")
          expect(output).to include("Repository: test/repo")
        end
      end
    end
  end

  describe "soba issue list" do
    it "requires repository argument" do
      output, error, status = Open3.capture3("#{soba_bin} issue list 2>&1")
      expect(status).not_to be_success
      expect(output + error).to include("repository is required")
    end

    it "lists issues when repository is provided" do
      output, status = Open3.capture2("#{soba_bin} issue list owner/repo")
      expect(status).to be_success
      expect(output).to include("Repository: owner/repo")
    end
  end

  describe "soba start" do
    it "shows start command in help" do
      output, status = Open3.capture2("#{soba_bin} --help")
      expect(status).to be_success
      expect(output).to include("start")
    end

    context "ワークフロー実行モード（引数なし）" do
      it "設定エラーの場合適切なメッセージを表示" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            output, error, status = Open3.capture3("#{soba_bin} start 2>&1")
            expect(status).not_to be_success
            expect(output + error).to include("GitHub repository is not set")
          end
        end
      end
    end

    context "単一Issue実行モード（Issue番号指定）" do
      it "Issue番号なしでエラーメッセージを表示" do
        output, error, status = Open3.capture3("#{soba_bin} start \"\" 2>&1")
        expect(status).not_to be_success
        expect(output + error).to include("Error: Issue number is required")
      end

      it "--no-tmuxオプションが利用可能" do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            # テスト用設定を作成してエラーを回避
            FileUtils.mkdir_p('.soba')
            File.write('.soba/config.yml', <<~YAML)
              github:
                token: test_token
                repository: test/repo
              workflow:
                use_tmux: true
            YAML

            output, error, _status = Open3.capture3("#{soba_bin} start 123 --no-tmux 2>&1")
            # メッセージが表示されることを確認（IssueProcessorのエラーは想定内）
            expect(output + error).to include("Running in direct mode")
          end
        end
      end
    end
  end
end