# frozen_string_literal: true

require "spec_helper"

RSpec.describe "soba.gemspec" do
  let(:gemspec_path) { File.expand_path("../soba.gemspec", __dir__) }
  let(:spec) { nil }

  before do
    # gemspecファイルが存在する場合のみ読み込む
    if File.exist?(gemspec_path)
      @spec = Gem::Specification.load(gemspec_path)
    end
  end

  describe "gemspecファイルの存在" do
    it "soba.gemspecファイルが存在すること" do
      expect(File.exist?(gemspec_path)).to be true
    end
  end

  context "gemspecが存在する場合" do
    before do
      skip "gemspecファイルがまだ作成されていません" unless File.exist?(gemspec_path)
    end

    describe "必須フィールドの検証" do
      it "nameフィールドが設定されていること" do
        expect(@spec.name).to eq("soba")
      end

      it "versionフィールドが正しく設定されていること" do
        expect(@spec.version.to_s).to eq(Soba::VERSION)
      end

      it "authorsフィールドが設定されていること" do
        expect(@spec.authors).not_to be_empty
      end

      it "emailフィールドが設定されていること" do
        expect(@spec.email).not_to be_empty
      end

      it "summaryフィールドが設定されていること" do
        expect(@spec.summary).not_to be_nil
        expect(@spec.summary.length).to be > 0
      end

      it "descriptionフィールドが設定されていること" do
        expect(@spec.description).not_to be_nil
        expect(@spec.description.length).to be > 0
      end

      it "homepageフィールドが設定されていること" do
        expect(@spec.homepage).to match(%r{https?://})
      end

      it "licenseフィールドが設定されていること" do
        expect(@spec.license).to eq("MIT")
      end
    end

    describe "Rubyバージョン要件" do
      it "required_ruby_versionが設定されていること" do
        expect(@spec.required_ruby_version).not_to be_nil
      end

      it "Ruby 3.0以上が要求されていること" do
        expect(@spec.required_ruby_version.to_s).to match(/>=\s*3\.0/)
      end
    end

    describe "実行ファイル設定" do
      it "実行ファイルが設定されていること" do
        expect(@spec.executables).to include("soba")
      end

      it "bindirがbinディレクトリに設定されていること" do
        expect(@spec.bindir).to eq("bin")
      end

      it "bin/sobaファイルが存在すること" do
        bin_path = File.join(File.dirname(gemspec_path), "bin", "soba")
        expect(File.exist?(bin_path)).to be true
      end
    end

    describe "ファイルリスト" do
      it "filesフィールドが設定されていること" do
        expect(@spec.files).not_to be_empty
      end

      it "必要なディレクトリが含まれていること" do
        expect(@spec.files).to include(a_string_matching(/^lib\//))
        expect(@spec.files).to include(a_string_matching(/^bin\//))
      end

      it "不要なファイルが含まれていないこと" do
        expect(@spec.files).not_to include(a_string_matching(/^spec\//))
        expect(@spec.files).not_to include(a_string_matching(/^test\//))
        expect(@spec.files).not_to include(a_string_matching(/\.git/))
      end
    end

    describe "実行時依存関係" do
      let(:runtime_deps) { @spec.runtime_dependencies.map(&:name) }

      it "GLI gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("gli")
      end

      it "dry-container gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("dry-container")
      end

      it "dry-auto_inject gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("dry-auto_inject")
      end

      it "faraday gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("faraday")
      end

      it "octokit gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("octokit")
      end

      it "concurrent-ruby gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("concurrent-ruby")
      end

      it "semantic_logger gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("semantic_logger")
      end

      it "dry-configurable gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("dry-configurable")
      end

      it "activesupport gemが依存関係に含まれていること" do
        expect(runtime_deps).to include("activesupport")
      end
    end

    describe "開発時依存関係" do
      let(:dev_deps) { @spec.development_dependencies.map(&:name) }

      it "開発時依存関係が存在しないこと（Gemfileで管理）" do
        # 開発時依存関係はGemfileで管理するため、gemspecには含めない
        expect(dev_deps).to be_empty
      end
    end

    describe "メタデータ" do
      it "source_code_uriが設定されていること" do
        expect(@spec.metadata["source_code_uri"]).to match(%r{https?://})
      end

      it "changelog_uriが設定されていること（オプション）" do
        # オプショナルなのでnilでも良い
        if @spec.metadata["changelog_uri"]
          expect(@spec.metadata["changelog_uri"]).to match(%r{https?://})
        end
      end
    end
  end
end