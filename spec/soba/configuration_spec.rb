# frozen_string_literal: true

require 'spec_helper'
require 'soba/configuration'
require 'tmpdir'

RSpec.describe Soba::Configuration do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(tmp_dir, '.soba') }
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

        # Mock GitHubTokenProvider to indicate no token is available
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:fetch).with(auth_method: nil).and_raise(
          Soba::Infrastructure::GitHubTokenProvider::TokenFetchError, "No GitHub token available"
        )

        expect { described_class.load!(path: config_file) }.to raise_error(
          Soba::ConfigurationError,
          /GitHub token is not available/
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

  describe 'auto-merge configuration' do
    context 'when auto_merge_enabled is not specified' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'defaults to true' do
        config = described_class.load!(path: config_file)
        expect(config.workflow.auto_merge_enabled).to be true
      end
    end

    context 'when auto_merge_enabled is explicitly set to false' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
            auto_merge_enabled: false
        YAML
      end

      it 'loads as false' do
        config = described_class.load!(path: config_file)
        expect(config.workflow.auto_merge_enabled).to be false
      end
    end

    context 'when auto_merge_enabled is explicitly set to true' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
            auto_merge_enabled: true
        YAML
      end

      it 'loads as true' do
        config = described_class.load!(path: config_file)
        expect(config.workflow.auto_merge_enabled).to be true
      end
    end
  end

  describe 'slack.notifications_enabled setting' do
    context 'when notifications_enabled is not set' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'defaults to false' do
        config = described_class.load!(path: config_file)
        expect(config.slack.notifications_enabled).to be false
      end
    end

    context 'when notifications_enabled is explicitly set to true' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          slack:
            webhook_url: 'https://hooks.slack.com/services/TEST'
            notifications_enabled: true
        YAML
      end

      it 'loads as true' do
        config = described_class.load!(path: config_file)
        expect(config.slack.notifications_enabled).to be true
        expect(config.slack.webhook_url).to eq('https://hooks.slack.com/services/TEST')
      end
    end

    context 'when notifications_enabled is explicitly set to false' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          slack:
            webhook_url: 'https://hooks.slack.com/services/TEST'
            notifications_enabled: false
        YAML
      end

      it 'loads as false' do
        config = described_class.load!(path: config_file)
        expect(config.slack.notifications_enabled).to be false
      end
    end
  end

  describe 'phase configuration' do
    context 'when phase settings are provided' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
          phase:
            plan:
              command: claude
              options:
                - --dangerously-skip-permissions
              parameter: '/osoba:plan {{issue-number}}'
            implement:
              command: claude
              options:
                - --dangerously-skip-permissions
              parameter: '/osoba:implement {{issue-number}}'
            review:
              command: claude
              options:
                - --dangerously-skip-permissions
              parameter: '/soba:review {{issue-number}}'
        YAML
      end

      it 'loads phase configuration correctly' do
        config = described_class.load!(path: config_file)

        expect(config.phase.plan.command).to eq('claude')
        expect(config.phase.plan.options).to eq(['--dangerously-skip-permissions'])
        expect(config.phase.plan.parameter).to eq('/osoba:plan {{issue-number}}')

        expect(config.phase.implement.command).to eq('claude')
        expect(config.phase.implement.options).to eq(['--dangerously-skip-permissions'])
        expect(config.phase.implement.parameter).to eq('/osoba:implement {{issue-number}}')

        expect(config.phase.review.command).to eq('claude')
        expect(config.phase.review.options).to eq(['--dangerously-skip-permissions'])
        expect(config.phase.review.parameter).to eq('/soba:review {{issue-number}}')
      end
    end

    context 'when phase settings are not provided' do
      before do
        described_class.reset_config
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'has nil values for phase configuration' do
        config = described_class.load!(path: config_file)

        expect(config.phase.plan.command).to be_nil
        expect(config.phase.implement.command).to be_nil
        expect(config.phase.review.command).to be_nil
      end
    end
  end

  describe 'auth_method configuration' do
    context 'when auth_method is not specified' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'defaults to nil (auto-detect)' do
        config = described_class.load!(path: config_file)
        expect(config.github.auth_method).to be_nil
      end
    end

    context 'when auth_method is set to "gh"' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            auth_method: gh
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'loads auth_method as "gh"' do
        # Mock gh command availability check
        allow_any_instance_of(Soba::Infrastructure::GitHubTokenProvider).to receive(:gh_available?).and_return(true)
        allow_any_instance_of(Soba::Infrastructure::GitHubTokenProvider).to receive(:fetch).with(auth_method: 'gh').and_return('gh_token')

        config = described_class.load!(path: config_file)
        expect(config.github.auth_method).to eq('gh')
      end
    end

    context 'when auth_method is set to "env"' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            auth_method: env
            repository: owner/repo
          workflow:
            interval: 20
        YAML
        ENV['GITHUB_TOKEN'] = 'env_test_token'
      end

      after do
        ENV.delete('GITHUB_TOKEN')
      end

      it 'loads auth_method as "env"' do
        config = described_class.load!(path: config_file)
        expect(config.github.auth_method).to eq('env')
      end
    end

    context 'when auth_method is set to invalid value' do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, <<~YAML)
          github:
            auth_method: invalid
            repository: owner/repo
          workflow:
            interval: 20
        YAML
      end

      it 'raises validation error' do
        expect { described_class.load!(path: config_file) }.to raise_error(
          Soba::ConfigurationError,
          /Invalid auth_method: invalid/
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