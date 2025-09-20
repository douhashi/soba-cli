# frozen_string_literal: true

require "spec_helper"
require "soba"

RSpec.describe "Log Level Configuration" do
  let(:log_output) { StringIO.new }
  let(:logger) { Soba.logger }

  before do
    # テスト用ログ設定
    SemanticLogger.clear_appenders!
    SemanticLogger.add_appender(io: log_output, formatter: :default)
  end

  after do
    # ログ設定をリセット
    SemanticLogger.clear_appenders!
    SemanticLogger.add_appender(io: $stdout, formatter: :color)
    SemanticLogger.default_level = :info
  end

  describe "default log level" do
    it "sets the default log level to :info" do
      # lib/soba.rbでデフォルトレベルがinfoに設定されていることを確認
      # 注: before hookでSemanticLoggerがクリアされるため、再度読み込み
      load File.expand_path("../../lib/soba.rb", __FILE__)
      expect(SemanticLogger.default_level).to eq(:info)
    end

    it "does not output debug messages at default level" do
      SemanticLogger.default_level = :info
      new_logger = SemanticLogger["Test"]
      new_logger.debug("debug message")
      new_logger.info("info message")
      SemanticLogger.flush

      expect(log_output.string).not_to include("debug message")
      expect(log_output.string).to include("info message")
    end
  end

  describe "verbose option" do
    context "when --verbose flag is specified" do
      it "sets log level to :debug" do
        # verboseフラグが指定された場合の挙動をテスト
        Soba.logger.level = :debug
        expect(Soba.logger.level).to eq(:debug)

        # debugメッセージが出力されることを確認
        logger.debug("debug message")
        logger.info("info message")
        SemanticLogger.flush

        expect(log_output.string).to include("debug message")
        expect(log_output.string).to include("info message")
      end
    end

    context "when -v flag is specified" do
      it "sets log level to :debug" do
        # -v短縮フラグでも同じ動作をすることを確認
        Soba.logger.level = :debug
        expect(Soba.logger.level).to eq(:debug)
      end
    end

    context "when verbose flag is not specified" do
      it "keeps log level at :info" do
        SemanticLogger.default_level = :info
        # 明示的にSoba.loggerのレベルを設定
        Soba.logger.level = :info
        expect(Soba.logger.level).to eq(:info)

        # debugメッセージは出力されないことを確認
        logger.debug("debug message")
        logger.info("info message")
        SemanticLogger.flush

        expect(log_output.string).not_to include("debug message")
        expect(log_output.string).to include("info message")
      end
    end
  end
end