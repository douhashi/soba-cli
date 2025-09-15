# frozen_string_literal: true

module Soba
  module Domain
    class Issue
      attr_reader :id, :number, :title, :body, :state, :labels, :created_at, :updated_at

      def initialize(attributes = {})
        @id = attributes[:id]
        @number = attributes[:number]
        @title = attributes[:title]
        @body = attributes[:body]
        @state = attributes[:state]
        @labels = attributes[:labels] || []
        @created_at = attributes[:created_at]
        @updated_at = attributes[:updated_at]
      end

      def open?
        state == "open"
      end

      def closed?
        state == "closed"
      end

      def has_label?(label_name)
        labels.any? { |label| label[:name] == label_name }
      end

      def priority
        return :high if has_label?("critical") || has_label?("urgent")
        return :medium if has_label?("important")
        :low
      end
    end
  end
end