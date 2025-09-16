# frozen_string_literal: true

require 'spec_helper'
require 'soba/configuration'
require 'tmpdir'

RSpec.describe Soba::Configuration do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(tmp_dir, '.osoba') }
  let(:config_file) { File.join(config_dir, 'config.yml') }

  before do
    described_class.reset_config
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    described_class.reset_config
  end

  describe '.load!' do
    context 'when config file does not exist' do
      it 'creates a default config file' do
        expect(File.exist?(config_file)).to be false

        allow(described_class).to receive(:find_project_root).and_return(Pathname.new(tmp_dir))
        allow(described_class).to receive(:validate!)

        described_class.load!

        expect(File.exist?(config_file)).to be true
      end
    end

    context 'when config file exists' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token_123
            repository: owner/repo
          workflow:
            interval: 30
        YAML
      end

      it 'loads configuration from file' do
        config = described_class.load!(path: config_file)

        expect(config.github.token).to eq('test_token_123')
        expect(config.github.repository).to eq('owner/repo')
        expect(config.workflow.interval).to eq(30)
      end

      it 'supports environment variable interpolation' do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: ${GITHUB_TOKEN}
            repository: owner/repo
          workflow:
            interval: 25
        YAML

        ENV['GITHUB_TOKEN'] = 'env_token_456'

        config = described_class.load!(path: config_file)

        expect(config.github.token).to eq('env_token_456')
      ensure
        ENV.delete('GITHUB_TOKEN')
      end
    end

    context 'validation' do
      before do
        FileUtils.mkdir_p(config_dir)
      end

      it 'raises error when GitHub token is missing' do
        File.write(config_file, <<~YAML)
          github:
            repository: owner/repo
          workflow:
            interval: 20
        YAML

        # Temporarily clear GITHUB_TOKEN environment variable
        original_token = ENV['GITHUB_TOKEN']
        ENV['GITHUB_TOKEN'] = nil

        expect { described_class.load!(path: config_file) }.to raise_error(
          Soba::ConfigurationError,
          /GitHub token is not set/
        )
      ensure
        # Restore original token
        ENV['GITHUB_TOKEN'] = original_token
      end

      it 'raises error when repository is missing' do
        File.write(config_file, <<~YAML)
          github:
            token: test_token
          workflow:
            interval: 20
        YAML

        expect { described_class.load!(path: config_file) }.to raise_error(
          Soba::ConfigurationError,
          /GitHub repository is not set/
        )
      end

      it 'raises error when interval is not positive' do
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 0
        YAML

        expect { described_class.load!(path: config_file) }.to raise_error(
          Soba::ConfigurationError,
          /Workflow interval must be positive/
        )
      end
    end
  end

  describe 'default values' do
    it 'sets default interval to 20 seconds' do
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, <<~YAML)
        github:
          token: test_token
          repository: owner/repo
      YAML

      config = described_class.load!(path: config_file)

      expect(config.workflow.interval).to eq(20)
    end

    it 'uses GITHUB_TOKEN from environment when not in config' do
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, <<~YAML)
        github:
          repository: owner/repo
        workflow:
          interval: 20
      YAML

      ENV['GITHUB_TOKEN'] = 'env_token_default'

      config = described_class.load!(path: config_file)

      expect(config.github.token).to eq('env_token_default')
    ensure
      ENV.delete('GITHUB_TOKEN')
    end
  end
end