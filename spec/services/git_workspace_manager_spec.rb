# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/git_workspace_manager'

RSpec.describe Soba::Services::GitWorkspaceManager do
  let(:issue_number) { 36 }
  let(:worktree_path) { '.git/soba/worktrees/issue-36' }
  let(:branch_name) { 'soba/36' }
  let(:configuration) do
    double('configuration',
      config: double(git: double(worktree_base_path: '.git/soba/worktrees', setup_workspace: true)))
  end
  let(:manager) { described_class.new(configuration: configuration) }

  describe '#setup_workspace' do
    context '正常系' do
      it 'worktreeを作成する（mainブランチ更新は行わない）' do
        expect(FileUtils).to receive(:mkdir_p).with('.git/soba/worktrees')
        expect(Open3).to receive(:capture3).
          with("git worktree add -b #{branch_name} #{worktree_path} origin/main").
          and_return(['', '', double(success?: true)])

        result = manager.setup_workspace(issue_number)
        expect(result).to be true
      end

      it '既存のworktreeが存在する場合はスキップする' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(true)
        expect(Open3).not_to receive(:capture3)

        result = manager.setup_workspace(issue_number)
        expect(result).to be true
      end
    end

    context 'エラー系' do
      it 'worktree追加が失敗した場合は例外を発生させる' do
        expect(FileUtils).to receive(:mkdir_p).with('.git/soba/worktrees')
        expect(Open3).to receive(:capture3).
          with("git worktree add -b #{branch_name} #{worktree_path} origin/main").
          and_return(['', 'error: failed to add worktree', double(success?: false)])

        expect do
          manager.setup_workspace(issue_number)
        end.to raise_error(Soba::Services::GitWorkspaceManager::GitOperationError, /Failed to create worktree/)
      end
    end
  end

  describe '#cleanup_workspace' do
    context '正常系' do
      it 'worktreeを削除する' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(true)
        expect(Open3).to receive(:capture3).
          with("git worktree remove #{worktree_path} --force").
          and_return(['', '', double(success?: true)])

        result = manager.cleanup_workspace(issue_number)
        expect(result).to be true
      end

      it 'worktreeが存在しない場合はスキップする' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(false)
        expect(Open3).not_to receive(:capture3)

        result = manager.cleanup_workspace(issue_number)
        expect(result).to be true
      end
    end

    context 'エラー系' do
      it 'worktree削除が失敗した場合は例外を発生させる' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(true)
        expect(Open3).to receive(:capture3).
          with("git worktree remove #{worktree_path} --force").
          and_return(['', 'error: failed to remove', double(success?: false)])

        expect do
          manager.cleanup_workspace(issue_number)
        end.to raise_error(Soba::Services::GitWorkspaceManager::GitOperationError, /Failed to remove worktree/)
      end
    end
  end

  describe '#worktree_path' do
    it 'Issue番号からworktreeパスを生成する' do
      expect(manager.send(:worktree_path, issue_number)).to eq(worktree_path)
    end
  end

  describe '#branch_name' do
    it 'Issue番号からブランチ名を生成する' do
      expect(manager.send(:branch_name, issue_number)).to eq(branch_name)
    end
  end

  describe '#get_worktree_path' do
    context 'when worktree exists' do
      it 'returns the worktree path' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(true)

        path = manager.get_worktree_path(issue_number)
        expect(path).to eq(worktree_path)
      end
    end

    context 'when worktree does not exist' do
      it 'returns nil' do
        expect(Dir).to receive(:exist?).with(worktree_path).and_return(false)

        path = manager.get_worktree_path(issue_number)
        expect(path).to be_nil
      end
    end
  end

  describe '#update_main_branch' do
    context 'when called as public method' do
      it 'updates the main branch successfully' do
        expect(Open3).to receive(:capture3).with('git fetch origin').and_return(['', '', double(success?: true)])
        expect(Open3).to receive(:capture3).with('git checkout main').and_return(['', '', double(success?: true)])
        expect(Open3).to receive(:capture3).with('git pull origin main').and_return(['', '', double(success?: true)])

        expect { manager.update_main_branch }.not_to raise_error
      end

      it 'raises error when fetch fails' do
        expect(Open3).to receive(:capture3).with('git fetch origin').
          and_return(['', 'error: failed to fetch', double(success?: false)])

        expect do
          manager.update_main_branch
        end.to raise_error(Soba::Services::GitWorkspaceManager::GitOperationError, /Failed to fetch/)
      end

      it 'raises error when checkout fails' do
        expect(Open3).to receive(:capture3).with('git fetch origin').and_return(['', '', double(success?: true)])
        expect(Open3).to receive(:capture3).with('git checkout main').
          and_return(['', 'error: failed to checkout', double(success?: false)])

        expect do
          manager.update_main_branch
        end.to raise_error(Soba::Services::GitWorkspaceManager::GitOperationError, /Failed to checkout/)
      end

      it 'raises error when pull fails' do
        expect(Open3).to receive(:capture3).with('git fetch origin').and_return(['', '', double(success?: true)])
        expect(Open3).to receive(:capture3).with('git checkout main').and_return(['', '', double(success?: true)])
        expect(Open3).to receive(:capture3).with('git pull origin main').
          and_return(['', 'error: failed to pull', double(success?: false)])

        expect do
          manager.update_main_branch
        end.to raise_error(Soba::Services::GitWorkspaceManager::GitOperationError, /Failed to pull/)
      end
    end
  end
end