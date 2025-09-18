# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

# Load custom rake tasks
Dir.glob('lib/tasks/*.rake').each { |r| import r }

task default: [:rubocop, :spec]

desc "Run tests with coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task["spec"].invoke
end