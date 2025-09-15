# frozen_string_literal: true

module Soba
  module Commands
    module Issue
      class List
        def execute(repository:, state:, config:)
          Soba.logger.info("Listing #{state} issues from #{repository}")

          puts "Repository: #{repository}"
          puts "State: #{state}"
          puts "Config: #{config}"
          puts "\nThis is a skeleton implementation."
        end
      end
    end
  end
end