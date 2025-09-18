# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tebako関連機能の削除' do
  describe 'ファイルの削除確認' do
    it 'Tebakoビルドスクリプトが削除されている' do
      expect(File.exist?('scripts/build-tebako.sh')).to be false
    end

    it 'Rakeタスクファイルが削除されている' do
      expect(File.exist?('lib/tasks/build.rake')).to be false
    end

    it 'Tebako関連のテストファイルが削除されている' do
      expect(File.exist?('spec/integration/tebako_build_spec.rb')).to be false
      expect(File.exist?('spec/scripts/build_tebako_spec.rb')).to be false
      expect(File.exist?('spec/tasks/build_tebako_rake_spec.rb')).to be false
    end

    it 'GitHub Actionsワークフローが削除されている' do
      expect(File.exist?('.github/workflows/release.yml')).to be false
    end

    it 'リリースプロセスドキュメントが削除されている' do
      expect(File.exist?('docs/development/release-process.md')).to be false
    end
  end

  describe '.gitignoreの更新' do
    it 'Tebako関連のエントリーが削除されている' do
      content = File.read('.gitignore')
      expect(content).not_to include('/dist/')
      expect(content).not_to include('# Tebako build artifacts')
    end
  end

  describe 'ドキュメントの更新' do
    it 'distribution.mdからTebako関連の記述が削除されている' do
      content = File.read('docs/development/distribution.md')
      expect(content).not_to include('Tebako')
      expect(content).not_to include('バイナリビルド')
      expect(content).to include('現在検討中')
    end

    it 'docs/development/INDEX.mdからrelease-process.mdのエントリーが削除されている' do
      content = File.read('docs/development/INDEX.md')
      expect(content).not_to include('release-process.md')
    end
  end

  describe 'Rakeタスクの削除' do
    it 'Tebakoタスクが存在しない' do
      tasks = `bundle exec rake -T 2>/dev/null`
      expect(tasks).not_to include('build:tebako')
      expect(tasks).not_to include('build:test_binary')
      expect(tasks).not_to include('build:clean')
    end
  end
end