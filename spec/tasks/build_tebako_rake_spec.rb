# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'build:tebako rake task' do
  let(:project_root) { File.expand_path('../..', File.dirname(__FILE__)) }

  describe 'task definition via command line' do
    it 'is defined and listed in rake tasks' do
      stdout, _stderr, status = Open3.capture3('rake -T build:tebako', chdir: project_root)
      expect(status).to be_success
      expect(stdout).to include('build:tebako')
      expect(stdout).to include('Build soba CLI as a standalone binary using Tebako')
    end

    it 'is available in all tasks list' do
      stdout, _stderr, status = Open3.capture3('rake -T', chdir: project_root)
      expect(status).to be_success
      expect(stdout).to include('build:tebako')
    end
  end

  describe 'task structure verification' do
    it 'has the correct rake file structure' do
      rake_file = File.join(project_root, 'lib/tasks/build.rake')
      expect(File.exist?(rake_file)).to be true

      content = File.read(rake_file)
      expect(content).to include('namespace :build')
      expect(content).to include('task tebako: :environment')
      expect(content).to include('scripts/build-tebako.sh')
    end
  end

  describe 'dependent tasks' do
    it 'includes environment task dependency' do
      rake_file = File.join(project_root, 'lib/tasks/build.rake')
      content = File.read(rake_file)
      expect(content).to include('task tebako: :environment')
    end

    it 'includes other build tasks' do
      rake_file = File.join(project_root, 'lib/tasks/build.rake')
      content = File.read(rake_file)
      expect(content).to include('task test_binary: :environment')
      expect(content).to include('task clean: :environment')
    end
  end
end