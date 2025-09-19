# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "gem rake tasks" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/gem", [File.expand_path("../../lib", __dir__)], [])
  end

  before(:each) do
    Rake::Task.tasks.each(&:reenable)
  end

  after(:all) do
    Rake.application = nil
  end

  describe "gem:build" do
    it "タスクが定義されていること" do
      expect(Rake::Task.task_defined?("gem:build")).to be true
    end

    it "gemファイルが作成されること" do
      allow_any_instance_of(Kernel).to receive(:system).and_return(true)
      expect { Rake::Task["gem:build"].invoke }.not_to raise_error
    end
  end

  describe "gem:install" do
    it "タスクが定義されていること" do
      expect(Rake::Task.task_defined?("gem:install")).to be true
    end

    it "gem:buildタスクに依存していること" do
      deps = Rake::Task["gem:install"].prerequisites
      expect(deps).to include("gem:build")
    end
  end

  describe "gem:uninstall" do
    it "タスクが定義されていること" do
      expect(Rake::Task.task_defined?("gem:uninstall")).to be true
    end

    it "gemがアンインストールされること" do
      allow_any_instance_of(Kernel).to receive(:system).and_return(true)
      expect { Rake::Task["gem:uninstall"].invoke }.not_to raise_error
    end
  end

  describe "gem:clean" do
    it "タスクが定義されていること" do
      expect(Rake::Task.task_defined?("gem:clean")).to be true
    end

    it "gemファイルが削除されること" do
      # ダミーのgemファイルを作成
      dummy_gem = "soba-0.0.0.gem"
      allow(Dir).to receive(:glob).and_return([dummy_gem])
      allow(File).to receive(:delete).with(dummy_gem)

      expect(File).to receive(:delete).with(dummy_gem)
      Rake::Task["gem:clean"].invoke
    end
  end

  describe "gem:release" do
    it "タスクが定義されていること" do
      expect(Rake::Task.task_defined?("gem:release")).to be true
    end

    it "gem:buildタスクに依存していること" do
      deps = Rake::Task["gem:release"].prerequisites
      expect(deps).to include("gem:build")
    end
  end
end