# frozen_string_literal: true

require "spec_helper"
require "soba/services/ansi_processor"

RSpec.describe Soba::Services::AnsiProcessor do
  let(:processor) { described_class.new }

  describe "#initialize" do
    it "デフォルト設定で初期化する" do
      expect(processor.instance_variable_get(:@preserve_colors)).to be(false)
      expect(processor.instance_variable_get(:@strip_codes)).to be(true)
    end

    it "カスタム設定で初期化できる" do
      custom_processor = described_class.new(preserve_colors: true, strip_codes: false)
      expect(custom_processor.instance_variable_get(:@preserve_colors)).to be(true)
      expect(custom_processor.instance_variable_get(:@strip_codes)).to be(false)
    end
  end

  describe "#process" do
    context "ANSIコードを削除する場合（デフォルト）" do
      it "色コードを削除する" do
        input = "\e[31mError:\e[0m Something went wrong"
        expected = "Error: Something went wrong"

        result = processor.process(input)
        expect(result).to eq(expected)
      end

      it "複数のANSIコードを削除する" do
        input = "\e[1m\e[32mSuccess!\e[0m\e[0m"
        expected = "Success!"

        result = processor.process(input)
        expect(result).to eq(expected)
      end

      it "カーソル移動コードを削除する" do
        input = "Loading\e[2K\e[1A\e[2KDone"
        expected = "LoadingDone"

        result = processor.process(input)
        expect(result).to eq(expected)
      end

      it "複雑なエスケープシーケンスを削除する" do
        input = "\e[?25h\e[?25lProcessing\e[?25h"
        expected = "Processing"

        result = processor.process(input)
        expect(result).to eq(expected)
      end
    end

    context "色を保持する場合" do
      let(:processor) { described_class.new(preserve_colors: true, strip_codes: false) }

      it "ANSIカラーコードをそのまま保持する" do
        input = "\e[31mError:\e[0m Something went wrong"

        result = processor.process(input)
        expect(result).to eq(input)
      end

      it "Paintライブラリ形式に変換できる" do
        processor = described_class.new(preserve_colors: true, strip_codes: false, convert_to_paint: true)
        input = "\e[31mError\e[0m"

        result = processor.process(input)
        # convert_to_paint_formatメソッドの実際の変換結果を期待
        expect(result).to eq("[[Error]]")
      end
    end

    context "エスケープ文字の処理" do
      it "キャリッジリターンを処理する" do
        input = "Progress: 10%\rProgress: 20%\rProgress: 30%"
        expected = "Progress: 30%"

        result = processor.process(input)
        expect(result).to eq(expected)
      end

      it "バックスペースを処理する" do
        input = "abc\b\bxy"
        expected = "axy"

        result = processor.process(input)
        expect(result).to eq(expected)
      end
    end

    context "空文字列やnilの処理" do
      it "空文字列を処理する" do
        result = processor.process("")
        expect(result).to eq("")
      end

      it "nilを空文字列として処理する" do
        result = processor.process(nil)
        expect(result).to eq("")
      end
    end
  end

  describe "#strip_ansi_codes" do
    it "すべてのANSIエスケープシーケンスを削除する" do
      input = "\e[1;31mBold Red\e[0m \e[32mGreen\e[0m \e[4mUnderline\e[0m"
      expected = "Bold Red Green Underline"

      result = processor.send(:strip_ansi_codes, input)
      expect(result).to eq(expected)
    end

    it "OSCシーケンスを削除する" do
      input = "\e]0;Terminal Title\a Normal text"
      expected = " Normal text"

      result = processor.send(:strip_ansi_codes, input)
      expect(result).to eq(expected)
    end
  end

  describe "#handle_control_chars" do
    it "キャリッジリターンで行を上書きする" do
      input = "First line\rSecond"
      expected = "Secondline"

      result = processor.send(:handle_control_chars, input)
      expect(result).to eq(expected)
    end

    it "複数のキャリッジリターンを処理する" do
      input = "aaa\rbbb\rccc"
      expected = "ccc"

      result = processor.send(:handle_control_chars, input)
      expect(result).to eq(expected)
    end

    it "バックスペースで文字を削除する" do
      input = "Hello\b\b\bli"
      expected = "Heli"

      result = processor.send(:handle_control_chars, input)
      expect(result).to eq(expected)
    end
  end
end