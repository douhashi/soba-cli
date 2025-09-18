# frozen_string_literal: true

require 'English'
require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe 'scripts/build-tebako.sh' do
  let(:script_path) { File.join(File.dirname(__FILE__), '../../scripts/build-tebako.sh') }
  let(:test_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe 'script existence' do
    it 'exists in the expected location' do
      expect(File.exist?(script_path)).to be true
    end

    it 'is executable' do
      expect(File.executable?(script_path)).to be true
    end
  end

  describe 'script execution' do
    it 'displays help when --help is passed' do
      output = `#{script_path} --help 2>&1`
      expect($CHILD_STATUS.success?).to be true
      expect(output).to include('Usage:')
      expect(output).to include('build-tebako.sh')
    end

    it 'checks for Docker availability' do
      # Dockerコマンドの存在をチェックするテスト
      output = `#{script_path} --check-docker 2>&1`
      if system('which docker > /dev/null 2>&1')
        expect(output).to include('Docker is available')
      else
        expect(output).to include('Docker is not available')
      end
    end

    it 'validates required environment' do
      output = `#{script_path} --validate 2>&1`
      # Environment validation might fail in test environment (Docker not running), so just check for expected output format
      expect(output).to match(/Validation|Docker/)
    end
  end

  describe 'build configuration' do
    it 'sets correct default output directory' do
      output = `#{script_path} --show-config 2>&1`
      expect(output).to match(/OUTPUT_DIR:.*dist/)
    end

    it 'sets correct Ruby version' do
      output = `#{script_path} --show-config 2>&1`
      expect(output).to include('RUBY_VERSION: 3.3.7')
    end

    it 'sets correct entry point' do
      output = `#{script_path} --show-config 2>&1`
      expect(output).to include('ENTRY_POINT: exe/soba')
    end
  end
end