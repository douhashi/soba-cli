# frozen_string_literal: true

require_relative 'configuration'

module Soba
  module ConfigLoader
    class << self
      def load(path: nil)
        Configuration.load!(path: path)
      rescue ConfigurationError => e
        handle_config_error(e)
      end

      def reload
        Configuration.reset_config
        load
      end

      def config
        @config ||= load
      end

      private

      def handle_config_error(error)
        puts "Configuration Error:"
        puts error.message
        puts "\nPlease check your .soba/config.yml file."
        exit 1
      end
    end
  end
end