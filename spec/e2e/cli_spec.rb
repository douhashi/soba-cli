# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "CLI", type: :e2e do
  let(:soba_bin) { File.expand_path("../../bin/soba", __dir__) }

  describe "soba --version" do
    it "displays version" do
      output, status = Open3.capture2("#{soba_bin} --version")
      expect(status).to be_success
      expect(output).to include(Soba::VERSION)
    end
  end

  describe "soba --help" do
    it "displays help message" do
      output, status = Open3.capture2("#{soba_bin} --help")
      expect(status).to be_success
      expect(output).to include("GitHub Issue to Claude Code workflow automation")
      expect(output).to include("issue")
      expect(output).to include("config")
    end
  end

  describe "soba config" do
    it "shows configuration" do
      output, status = Open3.capture2("#{soba_bin} config")
      expect(status).to be_success
      expect(output).to include("Config path:")
    end
  end

  describe "soba issue list" do
    it "requires repository argument" do
      output, error, status = Open3.capture3("#{soba_bin} issue list 2>&1")
      expect(status).not_to be_success
      expect(output + error).to include("repository is required")
    end

    it "lists issues when repository is provided" do
      output, status = Open3.capture2("#{soba_bin} issue list owner/repo")
      expect(status).to be_success
      expect(output).to include("Repository: owner/repo")
    end
  end
end