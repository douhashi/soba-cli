# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require_relative "../../config_loader"
require_relative "../../configuration"

module Soba
  module Commands
    module Config
      class Show
        def execute(config_path: nil)
          config = Soba::ConfigLoader.load(path: config_path)

          puts "=== soba Configuration ==="
          puts ""
          puts "GitHub:"
          puts "  Repository: #{config.github.repository}"
          puts "  Token: #{mask_token(config.github.token)}"
          puts ""
          puts "Workflow:"
          puts "  Interval: #{config.workflow.interval} seconds"
          puts ""
          puts "Configuration loaded from: #{find_config_path(config_path)}"
        rescue Soba::ConfigurationError => e
          puts "Configuration Error:"
          puts e.message
          exit 1
        end

        private

        def mask_token(token)
          return "Not set" if token.blank?

          if token.length > 8
            "#{token[0..3]}...#{token[-4..]}"
          else
            "*" * token.length
          end
        end

        def find_config_path(path)
          return path if path

          project_root = find_project_root
          return "Not found" unless project_root

          project_root.join('.osoba', 'config.yml')
        end

        def find_project_root
          current = Pathname.pwd

          until current.root?
            return current if current.join('.git').exist?
            current = current.parent
          end

          Pathname.pwd
        end
      end
    end
  end
end