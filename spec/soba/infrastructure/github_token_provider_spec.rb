# frozen_string_literal: true

require 'spec_helper'
require 'soba/infrastructure/github_token_provider'

RSpec.describe Soba::Infrastructure::GitHubTokenProvider do
  let(:provider) { described_class.new }

  describe '#fetch' do
    context 'when auth_method is "gh"' do
      context 'when gh command exists and returns a token' do
        let(:token) { 'ghp_test_token_1234567890' }

        before do
          allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
          allow(provider).to receive(:`).with('gh auth token 2>/dev/null').and_return(token)
          status = double('Process::Status', success?: true)
          allow(provider).to receive(:last_command_status).and_return(status)
        end

        it 'returns the token from gh command' do
          expect(provider.fetch(auth_method: 'gh')).to eq(token)
        end
      end

      context 'when gh command does not exist' do
        before do
          allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(false)
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: 'gh') }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /gh command not found/
          )
        end
      end

      context 'when gh auth token fails' do
        before do
          allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
          allow(provider).to receive(:`).with('gh auth token 2>/dev/null').and_return('')
          status = double('Process::Status', success?: false)
          allow(provider).to receive(:last_command_status).and_return(status)
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: 'gh') }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /Failed to get token from gh command/
          )
        end
      end

      context 'when gh returns empty token' do
        before do
          allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
          allow(provider).to receive(:`).with('gh auth token 2>/dev/null').and_return("\n")
          status = double('Process::Status', success?: true)
          allow(provider).to receive(:last_command_status).and_return(status)
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: 'gh') }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /gh auth token returned empty/
          )
        end
      end
    end

    context 'when auth_method is "env"' do
      context 'when GITHUB_TOKEN is set' do
        let(:token) { 'ghp_env_token_1234567890' }

        before do
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(token)
        end

        it 'returns the token from environment variable' do
          expect(provider.fetch(auth_method: 'env')).to eq(token)
        end
      end

      context 'when GITHUB_TOKEN is not set' do
        before do
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: 'env') }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /GITHUB_TOKEN environment variable not set/
          )
        end
      end

      context 'when GITHUB_TOKEN is empty' do
        before do
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('')
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: 'env') }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /GITHUB_TOKEN environment variable is empty/
          )
        end
      end
    end

    context 'when auth_method is nil or not specified' do
      context 'when gh command is available' do
        let(:token) { 'ghp_auto_token_1234567890' }

        before do
          allow(provider).to receive(:gh_available?).and_return(true)
          allow(provider).to receive(:fetch_from_gh).and_return(token)
        end

        it 'tries gh command first' do
          expect(provider.fetch(auth_method: nil)).to eq(token)
        end
      end

      context 'when gh command is not available but env is set' do
        let(:token) { 'ghp_env_fallback_1234567890' }

        before do
          allow(provider).to receive(:gh_available?).and_return(false)
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(token)
        end

        it 'falls back to environment variable' do
          expect(provider.fetch(auth_method: nil)).to eq(token)
        end
      end

      context 'when neither gh nor env is available' do
        before do
          allow(provider).to receive(:gh_available?).and_return(false)
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
        end

        it 'raises an error' do
          expect { provider.fetch(auth_method: nil) }.to raise_error(
            Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
            /No GitHub token available/
          )
        end
      end
    end

    context 'when auth_method is invalid' do
      it 'raises an error' do
        expect { provider.fetch(auth_method: 'invalid') }.to raise_error(
          Soba::Infrastructure::GitHubTokenProvider::TokenFetchError,
          /Invalid auth_method: invalid/
        )
      end
    end
  end

  describe '#gh_available?' do
    context 'when gh command exists and is authenticated' do
      before do
        allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
        allow(provider).to receive(:`).with('gh auth token 2>/dev/null').and_return('token')
        status = double('Process::Status', success?: true)
        allow(provider).to receive(:last_command_status).and_return(status)
      end

      it 'returns true' do
        expect(provider.gh_available?).to be true
      end
    end

    context 'when gh command does not exist' do
      before do
        allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(false)
      end

      it 'returns false' do
        expect(provider.gh_available?).to be false
      end
    end

    context 'when gh command exists but not authenticated' do
      before do
        allow(provider).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
        allow(provider).to receive(:`).with('gh auth token 2>/dev/null').and_return('')
        status = double('Process::Status', success?: false)
        allow(provider).to receive(:last_command_status).and_return(status)
      end

      it 'returns false' do
        expect(provider.gh_available?).to be false
      end
    end
  end

  describe '#detect_best_method' do
    context 'when gh is available' do
      before do
        allow(provider).to receive(:gh_available?).and_return(true)
      end

      it 'returns "gh"' do
        expect(provider.detect_best_method).to eq('gh')
      end
    end

    context 'when gh is not available but env is set' do
      before do
        allow(provider).to receive(:gh_available?).and_return(false)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('token')
      end

      it 'returns "env"' do
        expect(provider.detect_best_method).to eq('env')
      end
    end

    context 'when neither is available' do
      before do
        allow(provider).to receive(:gh_available?).and_return(false)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
      end

      it 'returns nil' do
        expect(provider.detect_best_method).to be_nil
      end
    end
  end
end