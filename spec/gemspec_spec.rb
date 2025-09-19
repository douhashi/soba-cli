# frozen_string_literal: true

require 'English'
require 'spec_helper'

RSpec.describe 'soba-cli.gemspec' do
  let(:gemspec_path) { File.expand_path('../soba-cli.gemspec', __dir__) }
  let(:gemspec) { Gem::Specification.load(gemspec_path) }

  describe 'gemspecファイルの存在' do
    it 'soba-cli.gemspecファイルが存在すること' do
      expect(File.exist?(gemspec_path)).to be true
    end

    it 'gemspecが正しくロードできること' do
      expect(gemspec).to be_a(Gem::Specification)
    end
  end

  describe 'メタデータ' do
    it '必須のメタデータが定義されていること' do
      expect(gemspec.name).to eq('soba-cli')
      expect(gemspec.version).not_to be_nil
      expect(gemspec.summary).not_to be_empty
      expect(gemspec.description).not_to be_empty
      expect(gemspec.authors).not_to be_empty
      expect(gemspec.email).not_to be_empty
      expect(gemspec.homepage).not_to be_empty
      expect(gemspec.license).to eq('MIT')
    end

    it 'バージョン情報が適切に読み込まれること' do
      expect(gemspec.version.to_s).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it 'Ruby 3.0以上を要求すること' do
      expect(gemspec.required_ruby_version.to_s).to include('>= 3.0')
    end
  end

  describe 'ファイル' do
    it '実行ファイルが含まれること' do
      expect(gemspec.executables).to include('soba')
    end

    it '必要なファイルが含まれること' do
      expect(gemspec.files).to include('lib/soba.rb')
      expect(gemspec.files).to include('lib/soba/version.rb')
      expect(gemspec.files).to include('bin/soba')
    end

    it 'specファイルが含まれないこと' do
      spec_files = gemspec.files.select { |f| f.start_with?('spec/') }
      expect(spec_files).to be_empty
    end
  end

  describe 'runtime依存関係' do
    let(:runtime_deps) { gemspec.runtime_dependencies.map(&:name) }

    it '必要なruntime依存関係が定義されていること' do
      expect(runtime_deps).to include('gli')
      expect(runtime_deps).to include('dry-container')
      expect(runtime_deps).to include('dry-auto_inject')
      expect(runtime_deps).to include('faraday')
      expect(runtime_deps).to include('faraday-retry')
      expect(runtime_deps).to include('octokit')
      expect(runtime_deps).to include('concurrent-ruby')
      expect(runtime_deps).to include('semantic_logger')
      expect(runtime_deps).to include('dry-configurable')
      expect(runtime_deps).to include('activesupport')
    end

    it 'runtime依存関係のバージョン制約が適切であること' do
      gli_dep = gemspec.runtime_dependencies.find { |d| d.name == 'gli' }
      expect(gli_dep.requirement.to_s).to match(/~> 2\.21/)

      octokit_dep = gemspec.runtime_dependencies.find { |d| d.name == 'octokit' }
      expect(octokit_dep.requirement.to_s).to match(/~> 8\.0/)
    end
  end

  describe 'development依存関係' do
    let(:dev_deps) { gemspec.development_dependencies.map(&:name) }

    it '必要なdevelopment依存関係が定義されていること' do
      expect(dev_deps).to include('rake')
      expect(dev_deps).to include('rspec')
      expect(dev_deps).to include('webmock')
      expect(dev_deps).to include('vcr')
      expect(dev_deps).to include('factory_bot')
      expect(dev_deps).to include('rubocop-airbnb')
      expect(dev_deps).to include('simplecov')
      expect(dev_deps).to include('bundler-audit')
      expect(dev_deps).to include('pry')
      expect(dev_deps).to include('pry-byebug')
    end

    it 'development依存関係のバージョン制約が適切であること' do
      rspec_dep = gemspec.development_dependencies.find { |d| d.name == 'rspec' }
      expect(rspec_dep.requirement.to_s).to match(/~> 3\.12/)

      rubocop_dep = gemspec.development_dependencies.find { |d| d.name == 'rubocop-airbnb' }
      expect(rubocop_dep.requirement.to_s).to match(/~> 6\.0/)
    end
  end

  describe 'gemビルド' do
    it 'gem buildコマンドが成功すること' do
      Dir.chdir(File.dirname(gemspec_path)) do
        output = `gem build soba-cli.gemspec 2>&1`
        expect($CHILD_STATUS).to be_success, "gem build failed: #{output}"
        expect(output).to include('Successfully built')

        # クリーンアップ
        gem_file = Dir.glob('soba-cli-*.gem').first
        if gem_file && File.exist?(gem_file)
          File.delete(gem_file)
        end
      end
    end
  end
end