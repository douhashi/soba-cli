# frozen_string_literal: true

module Soba
  module Services
    # ANSIエスケープシーケンスとコントロール文字の処理
    class AnsiProcessor
      def initialize(preserve_colors: false, strip_codes: true, convert_to_paint: false)
        @preserve_colors = preserve_colors
        @strip_codes = strip_codes
        @convert_to_paint = convert_to_paint
      end

      # テキストを処理
      def process(text)
        return "" if text.blank?

        processed = text.dup

        if @strip_codes
          processed = strip_ansi_codes(processed)
        elsif @convert_to_paint
          processed = convert_to_paint_format(processed)
          return processed # Paint形式の場合はcontrol文字処理をスキップ
        end

        handle_control_chars(processed)
      end

      private

      # ANSIエスケープシーケンスを削除
      def strip_ansi_codes(text)
        # CSI sequences (色、カーソル移動など)
        text = text.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")

        # OSC sequences (ターミナルタイトルなど)
        text = text.gsub(/\e\][^\a]*\a/, "")

        # その他のエスケープシーケンス
        text = text.gsub(/\e\[[\?!][0-9;]*[a-zA-Z]/, "")

        text
      end

      # Paint gem形式に変換（実装例）
      def convert_to_paint_format(text)
        # 簡易的な実装例
        # 実際にはPaint gemのAPIに合わせて実装
        text.gsub(/\e\[31m(.*?)\e\[0m/, '[[\1]]')
      end

      # コントロール文字の処理
      def handle_control_chars(text)
        lines = text.split("\n")

        lines.map! do |line|
          # キャリッジリターンの処理
          if line.include?("\r")
            parts = line.split("\r")
            # 最後の部分が現在の行
            current = parts.last || ""

            # 前の部分があれば、現在の行で上書き
            if parts.size > 1 && parts[-2]
              prev = parts[-2]
              if current.length < prev.length
                # 現在の行が短い場合、前の行の残りを追加
                current += prev[current.length..-1].to_s
              end
            end

            line = current
          end

          # バックスペースの処理
          while line.include?("\b")
            idx = line.index("\b")
            if idx && idx > 0
              line = line[0...idx - 1] + line[idx + 1..-1].to_s
            else
              line = line.sub("\b", "")
            end
          end

          line
        end

        lines.join("\n")
      end
    end
  end
end