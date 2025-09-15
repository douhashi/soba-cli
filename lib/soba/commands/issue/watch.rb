# frozen_string_literal: true

module Soba
  module Commands
    module Issue
      class Watch
        def execute(repository:, interval:, config:)
          Soba.logger.info("Watching #{repository} with interval #{interval}s")

          puts "Repository: #{repository}"
          puts "Interval: #{interval} seconds"
          puts "Config: #{config}"
          puts "\nThis is a skeleton implementation."
        end
      end
    end
  end
end