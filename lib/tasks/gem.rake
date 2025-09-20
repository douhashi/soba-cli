# frozen_string_literal: true

require_relative "../soba/version"

namespace :gem do
  desc "Build the soba-cli gem"
  task :build do
    puts "Building soba-cli gem..."
    system("gem build soba-cli.gemspec") || abort("Failed to build gem")
    puts "Gem built successfully!"
  end

  desc "Install the soba-cli gem locally"
  task install: "gem:build" do
    gem_file = Dir.glob("soba-cli-*.gem").max_by { |f| File.mtime(f) }
    abort("No gem file found") unless gem_file

    puts "Installing #{gem_file}..."
    system("gem install #{gem_file}") || abort("Failed to install gem")
    puts "Gem installed successfully!"
  end

  desc "Uninstall the soba-cli gem"
  task :uninstall do
    puts "Uninstalling soba-cli gem..."
    system("gem uninstall soba-cli -x") || puts("Gem may not be installed")
    puts "Gem uninstalled successfully!"
  end

  desc "Clean up built gem files"
  task :clean do
    gem_files = Dir.glob("soba-cli-*.gem")
    if gem_files.any?
      puts "Removing gem files: #{gem_files.join(', ')}"
      gem_files.each { |f| File.delete(f) }
      puts "Cleaned up gem files"
    else
      puts "No gem files to clean"
    end
  end

  desc "Build, tag, and push gem to RubyGems.org (manual release)"
  task release: "gem:build" do
    puts "🚨 NOTICE: This is a manual release task."
    puts "📋 For automated releases, create a GitHub Release with a tag like 'v1.2.3'"
    puts "🤖 GitHub Actions will automatically build and publish the gem."
    puts ""

    gem_file = Dir.glob("soba-cli-*.gem").max_by { |f| File.mtime(f) }
    abort("No gem file found") unless gem_file

    puts "WARNING: This will push #{gem_file} to RubyGems.org!"
    print "Are you sure you want to proceed with manual release? (y/N): "
    input = $stdin.gets.chomp

    if input.downcase == "y"
      system("gem push #{gem_file}") || abort("Failed to push gem")
      puts "Gem released successfully!"

      # Tag the release in git
      version = Soba::VERSION
      system("git tag v#{version}") || abort("Failed to create git tag")
      system("git push origin v#{version}") || abort("Failed to push git tag")
      puts "Git tag v#{version} created and pushed"
    else
      puts "Release cancelled"
    end
  end
end

desc "Alias for gem:build"
task build: "gem:build"

desc "Alias for gem:install"
task install: "gem:install"