# frozen_string_literal: true

require "dry-container"
require "dry-auto_inject"

module Soba
  class Container
    extend Dry::Container::Mixin

    namespace :github do
      register(:client) do
        require_relative "infrastructure/github_client"
        Infrastructure::GitHubClient.new
      end
    end

    namespace :tmux do
      register(:client) do
        require_relative "infrastructure/tmux_client"
        Infrastructure::TmuxClient.new
      end
    end

    namespace :services do
      register(:issue_monitor) do
        require_relative "services/issue_monitor"
        Services::IssueMonitor.new
      end

      register(:issue_watcher) do
        require_relative "services/issue_watcher"
        Services::IssueWatcher.new(github_client: Container["github.client"])
      end

      register(:tmux_session_manager) do
        require_relative "services/tmux_session_manager"
        Services::TmuxSessionManager.new(tmux_client: Container["tmux.client"])
      end

      register(:workflow_executor) do
        require_relative "workflow_executor"
        Services::WorkflowExecutor.new(tmux_session_manager: Container["services.tmux_session_manager"])
      end
    end
  end

  Import = Dry::AutoInject(Container)
end