# frozen_string_literal: true

require "spec_helper"

RSpec.describe Soba::Domain::Issue do
  let(:issue_attributes) do
    {
      id: 1,
      number: 123,
      title: "Test Issue",
      body: "Test body",
      state: "open",
      labels: [{ name: "bug" }, { name: "critical" }],
      created_at: Time.now,
      updated_at: Time.now,
    }
  end

  let(:issue) { described_class.new(issue_attributes) }

  describe "#initialize" do
    it "assigns attributes correctly" do
      expect(issue.id).to eq(1)
      expect(issue.number).to eq(123)
      expect(issue.title).to eq("Test Issue")
      expect(issue.body).to eq("Test body")
      expect(issue.state).to eq("open")
      expect(issue.labels).to eq([{ name: "bug" }, { name: "critical" }])
    end
  end

  describe "#open?" do
    context "when state is open" do
      it "returns true" do
        expect(issue.open?).to be true
      end
    end

    context "when state is closed" do
      let(:issue) { described_class.new(issue_attributes.merge(state: "closed")) }

      it "returns false" do
        expect(issue.open?).to be false
      end
    end
  end

  describe "#closed?" do
    context "when state is closed" do
      let(:issue) { described_class.new(issue_attributes.merge(state: "closed")) }

      it "returns true" do
        expect(issue.closed?).to be true
      end
    end

    context "when state is open" do
      it "returns false" do
        expect(issue.closed?).to be false
      end
    end
  end

  describe "#has_label?" do
    it "returns true when label exists" do
      expect(issue.has_label?("bug")).to be true
      expect(issue.has_label?("critical")).to be true
    end

    it "returns false when label does not exist" do
      expect(issue.has_label?("feature")).to be false
    end
  end

  describe "#priority" do
    context "with critical label" do
      it "returns high priority" do
        expect(issue.priority).to eq(:high)
      end
    end

    context "with urgent label" do
      let(:issue) do
        described_class.new(issue_attributes.merge(labels: [{ name: "urgent" }]))
      end

      it "returns high priority" do
        expect(issue.priority).to eq(:high)
      end
    end

    context "with important label" do
      let(:issue) do
        described_class.new(issue_attributes.merge(labels: [{ name: "important" }]))
      end

      it "returns medium priority" do
        expect(issue.priority).to eq(:medium)
      end
    end

    context "with no priority labels" do
      let(:issue) do
        described_class.new(issue_attributes.merge(labels: [{ name: "bug" }]))
      end

      it "returns low priority" do
        expect(issue.priority).to eq(:low)
      end
    end
  end
end