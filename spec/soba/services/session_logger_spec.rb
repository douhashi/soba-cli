# frozen_string_literal: true

require "spec_helper"
require "soba/services/session_logger"
require "tmpdir"
require "fileutils"

RSpec.describe Soba::Services::SessionLogger do
  let(:test_log_dir) { Dir.mktmpdir("soba-test-logs") }
  let(:logger) { described_class.new(log_dir: test_log_dir) }

  after do
    FileUtils.rm_rf(test_log_dir) if Dir.exist?(test_log_dir)
  end

  describe "#initialize" do
    it "指定したログディレクトリを使用する" do
      expect(logger.instance_variable_get(:@log_dir)).to eq(test_log_dir)
    end

    it "ディレクトリが存在しない場合は作成する" do
      new_dir = File.join(test_log_dir, "new_logs")
      described_class.new(log_dir: new_dir)
      expect(Dir.exist?(new_dir)).to be(true)
    end

    context "log_dirが指定されていない場合" do
      it "デフォルトのログディレクトリを使用する" do
        logger = described_class.new
        expected_dir = File.join(Dir.home, ".soba", "logs")
        expect(logger.instance_variable_get(:@log_dir)).to eq(expected_dir)
      end
    end
  end

  describe "#write" do
    let(:session_name) { "soba-21" }
    let(:content) { "test log content\n" }

    it "セッションログファイルに内容を書き込む" do
      logger.write(session_name, content)

      log_file = File.join(test_log_dir, "#{session_name}.log")
      expect(File.exist?(log_file)).to be(true)
      expect(File.read(log_file)).to include(content)
    end

    it "タイムスタンプを付けて書き込む" do
      allow(Time).to receive(:now).and_return(Time.new(2024, 12, 15, 10, 30, 45))

      logger.write(session_name, content)

      log_file = File.join(test_log_dir, "#{session_name}.log")
      expect(File.read(log_file)).to include("[2024-12-15 10:30:45]")
      expect(File.read(log_file)).to include(content)
    end

    it "複数回書き込みで追記される" do
      logger.write(session_name, "first line\n")
      logger.write(session_name, "second line\n")

      log_file = File.join(test_log_dir, "#{session_name}.log")
      content = File.read(log_file)
      expect(content).to include("first line")
      expect(content).to include("second line")
    end

    context "max_sizeが指定されている場合" do
      let(:logger) { described_class.new(log_dir: test_log_dir, max_size: 100) }

      it "最大サイズを超えたらローテートする" do
        # 100バイトを超えるコンテンツを書き込む
        logger.write(session_name, "a" * 150)

        log_file = File.join(test_log_dir, "#{session_name}.log")
        rotated_file = File.join(test_log_dir, "#{session_name}.log.1")

        expect(File.exist?(rotated_file)).to be(true)
        expect(File.size(log_file)).to be < 150
      end
    end
  end

  describe "#find_log" do
    let(:session_name) { "soba-21" }

    it "存在するログファイルのパスを返す" do
      log_file = File.join(test_log_dir, "#{session_name}.log")
      FileUtils.touch(log_file)

      result = logger.find_log(session_name)
      expect(result).to eq(log_file)
    end

    it "ログファイルが存在しない場合はnilを返す" do
      result = logger.find_log("non-existent")
      expect(result).to be_nil
    end
  end

  describe "#list_sessions" do
    before do
      ["soba-19", "soba-20", "soba-21"].each do |session|
        FileUtils.touch(File.join(test_log_dir, "#{session}.log"))
      end
      FileUtils.touch(File.join(test_log_dir, "other.log"))
    end

    it "sobaセッションのログファイル一覧を返す" do
      result = logger.list_sessions
      expect(result).to contain_exactly("soba-19", "soba-20", "soba-21")
    end

    it "ローテートされたファイルは除外する" do
      FileUtils.touch(File.join(test_log_dir, "soba-22.log.1"))

      result = logger.list_sessions
      expect(result).not_to include("soba-22.log.1")
    end
  end

  describe "#close" do
    it "開いているファイルハンドルを閉じる" do
      logger.write("soba-21", "test")
      file_handle = logger.instance_variable_get(:@file_handles)["soba-21"]

      expect(file_handle).to receive(:close)
      logger.close
    end

    it "すべてのファイルハンドルを閉じる" do
      logger.write("soba-21", "test1")
      logger.write("soba-22", "test2")

      logger.close

      handles = logger.instance_variable_get(:@file_handles)
      expect(handles).to be_empty
    end
  end

  describe "#cleanup_old_logs" do
    before do
      # 古いログファイルを作成（30日前）
      old_time = Time.now - (31 * 24 * 60 * 60)
      old_file = File.join(test_log_dir, "soba-old.log")
      FileUtils.touch(old_file)
      File.utime(old_time, old_time, old_file)

      # 新しいログファイル
      FileUtils.touch(File.join(test_log_dir, "soba-new.log"))
    end

    it "指定日数より古いログを削除する" do
      logger.cleanup_old_logs(days: 30)

      expect(File.exist?(File.join(test_log_dir, "soba-old.log"))).to be(false)
      expect(File.exist?(File.join(test_log_dir, "soba-new.log"))).to be(true)
    end
  end

  describe "#rotate_log" do
    let(:session_name) { "soba-21" }
    let(:log_file) { File.join(test_log_dir, "#{session_name}.log") }

    before do
      File.write(log_file, "original content")
    end

    it "ログファイルをローテートする" do
      logger.send(:rotate_log, session_name)

      rotated_file = File.join(test_log_dir, "#{session_name}.log.1")
      expect(File.exist?(rotated_file)).to be(true)
      expect(File.read(rotated_file)).to eq("original content")
      expect(File.exist?(log_file)).to be(true)
      expect(File.size(log_file)).to eq(0)
    end

    it "既存のローテートファイルがある場合は番号を増やす" do
      FileUtils.touch(File.join(test_log_dir, "#{session_name}.log.1"))

      logger.send(:rotate_log, session_name)

      expect(File.exist?(File.join(test_log_dir, "#{session_name}.log.2"))).to be(true)
    end
  end
end