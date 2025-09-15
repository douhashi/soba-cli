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

    namespace :services do
      register(:issue_monitor) do
        require_relative "services/issue_monitor"
        Services::IssueMonitor.new
      end
    end
  end

  Import = Dry::AutoInject(Container)
end