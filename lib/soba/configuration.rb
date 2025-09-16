# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'dry-configurable'
require 'yaml'
require 'pathname'

module Soba
  class Configuration
    extend Dry::Configurable

    setting :github do
      setting :token, default: ENV.fetch('GITHUB_TOKEN', nil)
      setting :repository
    end

    setting :workflow do
      setting :interval, default: 20
    end

    setting :phase do
      setting :plan do
        setting :command
        setting :options, default: []
        setting :parameter
      end
      setting :implement do
        setting :command
        setting :options, default: []
        setting :parameter
      end
    end

    class << self
      def reset_config
        @config = nil
        configure do |c|
          c.github.token = ENV.fetch('GITHUB_TOKEN', nil)
          c.github.repository = nil
          c.workflow.interval = 20
          c.phase.plan.command = nil
          c.phase.plan.options = []
          c.phase.plan.parameter = nil
          c.phase.implement.command = nil
          c.phase.implement.options = []
          c.phase.implement.parameter = nil
        end
      end

      def load!(path: nil)
        config_path = find_config_file(path)

        if config_path && File.exist?(config_path)
          load_from_file(config_path)
        else
          create_default_config(config_path || default_config_path)
        end

        validate!
        config
      end

      private

      def find_config_file(path)
        return Pathname.new(path) if path

        # プロジェクトルートの.soba/config.ymlを探す
        project_root = find_project_root
        return nil unless project_root

        project_root.join('.soba', 'config.yml')
      end

      def find_project_root
        current = Pathname.pwd

        until current.root?
          return current if current.join('.git').exist?
          current = current.parent
        end

        Pathname.pwd
      end

      def default_config_path
        find_project_root.join('.soba', 'config.yml')
      end

      def load_from_file(path)
        content = File.read(path)
        # 環境変数を展開
        expanded_content = content.gsub(/\$\{([^}]+)\}/) do |match|
          var_name = Regexp.last_match(1)
          ENV[var_name] || match
        end
        data = YAML.safe_load(expanded_content, permitted_classes: [Symbol])

        reset_config
        configure do |c|
          if data['github']
            c.github.token = data.dig('github', 'token') || ENV.fetch('GITHUB_TOKEN', nil)
            c.github.repository = data.dig('github', 'repository')
          end

          if data['workflow']
            c.workflow.interval = data.dig('workflow', 'interval') || 20
          end

          if data['phase']
            if data['phase']['plan']
              c.phase.plan.command = data.dig('phase', 'plan', 'command')
              c.phase.plan.options = data.dig('phase', 'plan', 'options') || []
              c.phase.plan.parameter = data.dig('phase', 'plan', 'parameter')
            end
            if data['phase']['implement']
              c.phase.implement.command = data.dig('phase', 'implement', 'command')
              c.phase.implement.options = data.dig('phase', 'implement', 'options') || []
              c.phase.implement.parameter = data.dig('phase', 'implement', 'parameter')
            end
          end
        end
      end

      def create_default_config(path)
        path.dirname.mkpath

        default_content = <<~YAML
          # soba CLI configuration
          github:
            # GitHub Personal Access Token
            # Can use environment variable: ${GITHUB_TOKEN}
            token: ${GITHUB_TOKEN}

            # Target repository (format: owner/repo)
            repository: # e.g., douhashi/soba

          workflow:
            # Issue polling interval in seconds
            interval: 20

          # Phase command configuration (optional)
          # phase:
          #   plan:
          #     command: claude
          #     options:
          #       - --dangerously-skip-permissions
          #     parameter: '/osoba:plan {{issue-number}}'
          #   implement:
          #     command: claude
          #     options:
          #       - --dangerously-skip-permissions
          #     parameter: '/osoba:implement {{issue-number}}'
        YAML

        File.write(path, default_content)
        puts "Created default configuration at: #{path}"
        puts "Please edit the configuration file and set your GitHub repository."
      end

      def validate!
        errors = []

        errors << "GitHub token is not set" if config.github.token.blank?
        errors << "GitHub repository is not set" if config.github.repository.blank?
        errors << "Workflow interval must be positive" if config.workflow.interval <= 0

        unless errors.empty?
          raise ConfigurationError, "Configuration errors:\n  #{errors.join("\n  ")}"
        end
      end
    end
  end
end