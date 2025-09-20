# frozen_string_literal: true

require "faraday"
require "json"

module Soba
  module Services
    class SlackNotifier
      def initialize(webhook_url:)
        @webhook_url = webhook_url
      end

      def notify_phase_start(issue_data)
        return false unless enabled?

        begin
          response = send_notification(build_message(issue_data))
          if response.success?
            true
          else
            logger.error("Failed to send Slack notification: HTTP #{response.status}")
            false
          end
        rescue StandardError => e
          logger.error("Error sending Slack notification: #{e.message}")
          false
        end
      end

      def enabled?
        @webhook_url.present?
      end

      def self.from_env
        new(webhook_url: ENV["SLACK_WEBHOOK_URL"])
      end

      def self.from_config
        config = Soba::Configuration.config
        return unless config.slack.notifications_enabled

        webhook_url = config.slack.webhook_url
        # 環境変数形式の場合は展開
        if webhook_url&.match?(/\$\{([^}]+)\}/)
          var_name = webhook_url.match(/\$\{([^}]+)\}/)[1]
          webhook_url = ENV[var_name]
        end

        new(webhook_url: webhook_url)
      end

      private

      def send_notification(message)
        connection = Faraday.new do |conn|
          conn.request :json
          conn.response :json
          conn.adapter Faraday.default_adapter
          conn.options.timeout = 5
          conn.options.open_timeout = 5
        end

        connection.post(@webhook_url, message.to_json)
      end

      def build_message(issue_data)
        {
          text: "🚀 Soba Workflow Phase Started: Issue ##{issue_data[:number]}",
          attachments: [
            {
              color: "good",
              title: issue_data[:title],
              fields: [
                {
                  title: "Issue",
                  value: "##{issue_data[:number]}",
                  short: true,
                },
                {
                  title: "Phase",
                  value: issue_data[:phase],
                  short: true,
                },
                {
                  title: "Title",
                  value: issue_data[:title],
                  short: false,
                },
              ],
              footer: "Soba CLI",
              footer_icon: "https://github.com/favicon.ico",
              ts: Time.now.to_i,
            },
          ],
        }
      end

      def logger
        @logger ||= if defined?(Soba.logger)
                      Soba.logger
                    else
                      require "logger"
                      Logger.new($stdout)
                    end
      end
    end
  end
end
