# frozen_string_literal: true

module Soba
  module Commands
    module Config
      class Show
        def execute(config_path:)
          Soba.logger.info("Showing configuration from #{config_path}")

          puts "Config path: #{config_path}"
          puts "\nThis is a skeleton implementation."
        end
      end
    end
  end
end