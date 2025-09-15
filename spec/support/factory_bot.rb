# frozen_string_literal: true

FactoryBot.define do
  factory :issue, class: "Soba::Domain::Issue" do
    id { 1 }
    number { 123 }
    title { "Test Issue" }
    body { "Test body" }
    state { "open" }
    labels { [] }
    created_at { Time.now }
    updated_at { Time.now }

    trait :with_labels do
      labels { [{ name: "bug" }, { name: "enhancement" }] }
    end

    trait :critical do
      labels { [{ name: "critical" }] }
    end

    trait :closed do
      state { "closed" }
    end

    initialize_with { new(attributes) }
  end
end