# frozen_string_literal: true

module Soba
  # Helper methods for blank? check
  module BlankHelper
    refine NilClass do
      def blank?
        true
      end
    end

    refine String do
      def blank?
        empty? || /\A\s*\z/.match?(self)
      end
    end
  end
end