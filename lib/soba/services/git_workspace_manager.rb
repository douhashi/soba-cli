# frozen_string_literal: true

require 'open3'
require 'fileutils'
require_relative '../configuration'

module Soba
  module Services
    class GitWorkspaceManager
      class GitOperationError < StandardError; end

      def initialize(configuration: nil)
        @configuration = configuration || Soba::Configuration
      end

      def setup_workspace(issue_number)
        worktree_path = worktree_path(issue_number)
        branch_name = branch_name(issue_number)

        # 既存のworktreeが存在する場合はスキップ
        if Dir.exist?(worktree_path)
          puts "Worktree already exists at #{worktree_path}, skipping setup"
          return true
        end

        # mainブランチを最新化
        update_main_branch

        # worktreeディレクトリを作成
        FileUtils.mkdir_p(@configuration.config.git.worktree_base_path)

        # worktreeを作成
        create_worktree(worktree_path, branch_name)

        true
      end

      def cleanup_workspace(issue_number)
        worktree_path = worktree_path(issue_number)

        # worktreeが存在しない場合はスキップ
        unless Dir.exist?(worktree_path)
          puts "Worktree does not exist at #{worktree_path}, skipping cleanup"
          return true
        end

        # worktreeを削除
        remove_worktree(worktree_path)

        true
      end

      def get_worktree_path(issue_number)
        path = worktree_path(issue_number)
        Dir.exist?(path) ? path : nil
      end

      private

      def worktree_path(issue_number)
        "#{@configuration.config.git.worktree_base_path}/issue-#{issue_number}"
      end

      def branch_name(issue_number)
        "soba/#{issue_number}"
      end

      def update_main_branch
        # git fetch origin
        _, stderr, status = Open3.capture3('git fetch origin')
        unless status.success?
          raise GitOperationError, "Failed to fetch from origin: #{stderr}"
        end

        # git checkout main
        _, stderr, status = Open3.capture3('git checkout main')
        unless status.success?
          raise GitOperationError, "Failed to checkout main branch: #{stderr}"
        end

        # git pull origin main
        _, stderr, status = Open3.capture3('git pull origin main')
        unless status.success?
          raise GitOperationError, "Failed to pull latest changes from main: #{stderr}"
        end
      end

      def create_worktree(worktree_path, branch_name)
        command = "git worktree add -b #{branch_name} #{worktree_path} origin/main"
        _, stderr, status = Open3.capture3(command)
        unless status.success?
          raise GitOperationError, "Failed to create worktree: #{stderr}"
        end
      end

      def remove_worktree(worktree_path)
        command = "git worktree remove #{worktree_path} --force"
        _, stderr, status = Open3.capture3(command)
        unless status.success?
          raise GitOperationError, "Failed to remove worktree: #{stderr}"
        end
      end
    end
  end
end