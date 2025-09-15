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
          FileUtils.mkdir_p('.osoba')
          File.write('.osoba/config.yml', config_content)

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
end