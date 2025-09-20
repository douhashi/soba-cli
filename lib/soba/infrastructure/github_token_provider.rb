# frozen_string_literal: true

require 'English'

module Soba
  module Infrastructure
    # rubocop:disable Airbnb/ModuleMethodInWrongFile
    class GitHubTokenProvider
      class TokenFetchError < StandardError; end

      def fetch(auth_method: nil)
        case auth_method
        when 'gh'
          fetch_from_gh
        when 'env'
          fetch_from_env
        when nil
          fetch_auto
        else
          raise TokenFetchError, "Invalid auth_method: #{auth_method}"
        end
      end

      def gh_available?
        return false unless system('which gh > /dev/null 2>&1')

        output = `gh auth token 2>/dev/null`
        last_command_status.success? && !output.strip.empty?
      end

      def detect_best_method
        return 'gh' if gh_available?
        return 'env' if ENV['GITHUB_TOKEN']

        nil
      end

      private

      def fetch_from_gh
        unless system('which gh > /dev/null 2>&1')
          raise TokenFetchError, 'gh command not found. Please install GitHub CLI'
        end

        token = `gh auth token 2>/dev/null`.strip

        unless last_command_status.success?
          raise TokenFetchError, 'Failed to get token from gh command. Please run `gh auth login` first'
        end

        if token.empty?
          raise TokenFetchError, 'gh auth token returned empty. Please run `gh auth login` first'
        end

        token
      end

      def last_command_status
        # Return the child process status, with nil check
        status = $CHILD_STATUS || $LAST_CHILD_STATUS

        # If both are nil, create a fake failed status
        if status.nil?
          # Create a stub status object that responds to success?
          Struct.new(:success?).new(false)
        else
          status
        end
      end

      def fetch_from_env
        token = ENV['GITHUB_TOKEN']

        if token.nil?
          raise TokenFetchError, 'GITHUB_TOKEN environment variable not set'
        end

        if token.empty?
          raise TokenFetchError, 'GITHUB_TOKEN environment variable is empty'
        end

        token
      end

      def fetch_auto
        if gh_available?
          fetch_from_gh
        elsif ENV['GITHUB_TOKEN']
          fetch_from_env
        else
          raise TokenFetchError,
                'No GitHub token available. Please set GITHUB_TOKEN environment variable or run `gh auth login`'
        end
      end
    end
    # rubocop:enable Airbnb/ModuleMethodInWrongFile
  end
end