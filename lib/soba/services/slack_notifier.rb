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

        logger.debug "Starting Slack notification for issue ##{issue_data[:number]}, phase: #{issue_data[:phase]}"

        begin
          message = build_message(issue_data)
          logger.debug "Sending notification to Slack webhook"

          response = send_notification(message)

          if response.success?
            logger.debug "Slack notification sent successfully (HTTP #{response.status})"
            true
          else
            logger.warn("Failed to send Slack notification: HTTP #{response.status}")
            false
          end
        rescue StandardError => e
          logger.warn("Error sending Slack notification: #{e.message}")
          false
        end
      end

      def notify_issue_merged(merge_data)
        return false unless enabled?

        logger.debug "Starting Slack notification for merged issue ##{merge_data[:issue_number]}"

        begin
          message = build_merged_message(merge_data)
          logger.debug "Sending notification to Slack webhook"

          response = send_notification(message)

          if response.success?
            logger.debug "Slack notification sent successfully (HTTP #{response.status})"
            true
          else
            logger.warn("Failed to send Slack notification: HTTP #{response.status}")
            false
          end
        rescue StandardError => e
          logger.warn("Error sending Slack notification: #{e.message}")
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
        issue_url = if issue_data[:repository]
                      "https://github.com/#{issue_data[:repository]}/issues/#{issue_data[:number]}"
                    else
                      "##{issue_data[:number]}"
                    end

        issue_value = if issue_data[:repository]
                        "<#{issue_url}|##{issue_data[:number]}>"
                      else
                        "##{issue_data[:number]}"
                      end

        {
          text: "🚀 Soba started #{issue_data[:phase]} phase: Issue ##{issue_data[:number]}",
          attachments: [
            {
              color: "good",
              title: issue_data[:title],
              fields: [
                {
                  title: "Issue",
                  value: issue_value,
                  short: true,
                },
                {
                  title: "Phase",
                  value: issue_data[:phase],
                  short: true,
                },
              ],
              footer: "Soba CLI",
              footer_icon: "https://github.com/favicon.ico",
              ts: Time.now.to_i,
            },
          ],
        }
      end

      def build_merged_message(merge_data)
        issue_url = if merge_data[:repository]
                      "https://github.com/#{merge_data[:repository]}/issues/#{merge_data[:issue_number]}"
                    else
                      "##{merge_data[:issue_number]}"
                    end

        issue_value = if merge_data[:repository]
                        "<#{issue_url}|##{merge_data[:issue_number]}>"
                      else
                        "##{merge_data[:issue_number]}"
                      end

        fields = [
          {
            title: "Issue",
            value: issue_value,
            short: true,
          },
        ]

        if merge_data[:pr_number] && merge_data[:repository]
          pr_url = "https://github.com/#{merge_data[:repository]}/pull/#{merge_data[:pr_number]}"
          pr_value = "<#{pr_url}|##{merge_data[:pr_number]}>"
          fields << {
            title: "PR",
            value: pr_value,
            short: true,
          }
        end

        if merge_data[:sha]
          fields << {
            title: "SHA",
            value: merge_data[:sha],
            short: true,
          }
        end

        {
          text: "✅ Soba merged: Issue ##{merge_data[:issue_number]}",
          attachments: [
            {
              color: "good",
              title: merge_data[:issue_title],
              fields: fields,
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
                      SemanticLogger["SlackNotifier"]
                    end
      end
    end
  end
end
