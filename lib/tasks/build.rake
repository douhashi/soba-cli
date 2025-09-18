# frozen_string_literal: true

namespace :build do
  desc "Build soba CLI as a standalone binary using Tebako"
  task tebako: :environment do
    script_path = File.join(File.dirname(__FILE__), '../../scripts/build-tebako.sh')

    puts "Building soba binary with Tebako..."
    puts "Running: #{script_path}"

    unless system(script_path)
      puts "Build failed!"
      exit(1)
    end

    puts "Build completed successfully!"
    puts "Binary is available in the dist/ directory"
  end

  desc "Test the built binary"
  task test_binary: :environment do
    script_path = File.join(File.dirname(__FILE__), '../../scripts/build-tebako.sh')

    puts "Testing built binary..."
    unless system(script_path, '--test')
      puts "Binary test failed!"
      exit(1)
    end

    puts "Binary test completed successfully!"
  end

  desc "Clean build artifacts"
  task clean: :environment do
    dist_dir = File.join(File.dirname(__FILE__), '../../dist')

    if Dir.exist?(dist_dir)
      puts "Cleaning build artifacts in #{dist_dir}..."
      FileUtils.rm_rf(dist_dir)
      puts "Cleaned successfully!"
    else
      puts "No build artifacts to clean"
    end
  end
end

task environment: [] do
  # Environment setup task (can be expanded if needed)
end