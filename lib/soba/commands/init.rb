# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/exclude"
require "pathname"
require "yaml"
require "io/console"

module Soba
  module Commands
    class Init
      def execute
        puts "🚀 Initializing soba configuration..."
        puts ""

        config_path = Pathname.pwd.join('.soba', 'config.yml')

        if config_path.exist?
          puts "⚠️  Configuration file already exists at: #{config_path}"
          print "Do you want to overwrite it? (y/N): "
          response = $stdin.gets.chomp.downcase
          if response != 'y' && response != 'yes'
            puts "✅ Configuration unchanged."
            return
          end
        end

        # Collect configuration values
        puts "Let's set up your GitHub configuration:"
        puts ""

        # GitHub repository - auto-detect from git remote
        default_repo = detect_github_repository

        if default_repo
          print "Enter GitHub repository (format: owner/repo) [#{default_repo}]: "
        else
          print "Enter GitHub repository (format: owner/repo): "
        end

        repository = $stdin.gets.chomp
        if repository.empty? && default_repo
          repository = default_repo
        end

        while repository.blank? || repository.exclude?('/')
          puts "❌ Invalid format. Please use: owner/repo"
          print "Enter GitHub repository: "
          repository = $stdin.gets.chomp
        end

        # GitHub token
        puts ""
        puts "GitHub Personal Access Token (PAT) setup:"
        puts "  1. Use environment variable ${GITHUB_TOKEN} (recommended)"
        puts "  2. Enter token directly (will be visible in config file)"
        print "Choose option (1-2) [1]: "
        token_option = $stdin.gets.chomp
        token_option = '1' if token_option.empty?

        token = if token_option == '2'
                  print "Enter GitHub token: "
                  # Hide input for security
                  $stdin.noecho(&:gets).chomp.tap { puts }
                else
                  '${GITHUB_TOKEN}'
                end

        # Polling interval
        puts ""
        print "Enter polling interval in seconds [20]: "
        interval = $stdin.gets.chomp
        interval = '20' if interval.empty?
        interval = interval.to_i
        interval = 20 if interval <= 0

        # Phase labels configuration
        puts ""
        puts "Phase labels configuration:"
        puts "These labels are used to track issue progress through the workflow"
        puts ""

        # Planning phase label
        print "Enter planning phase label [soba:planning]: "
        planning_label = $stdin.gets.chomp
        planning_label = 'soba:planning' if planning_label.empty?

        # Ready phase label
        print "Enter ready phase label [soba:ready]: "
        ready_label = $stdin.gets.chomp
        ready_label = 'soba:ready' if ready_label.empty?

        # Doing phase label
        print "Enter doing phase label [soba:doing]: "
        doing_label = $stdin.gets.chomp
        doing_label = 'soba:doing' if doing_label.empty?

        # Review requested phase label
        print "Enter review requested phase label [soba:review-requested]: "
        review_label = $stdin.gets.chomp
        review_label = 'soba:review-requested' if review_label.empty?

        # Workflow commands configuration
        puts ""
        puts "Workflow commands configuration (optional):"
        puts "These commands will be executed during each phase"
        puts ""

        # Plan phase command
        puts "Planning phase command:"
        print "Enter command (e.g., claude) [skip]: "
        plan_command = $stdin.gets.chomp
        if plan_command.empty? || plan_command.downcase == 'skip'
          plan_command = nil
        end

        plan_options = []
        plan_parameter = nil
        if plan_command
          print "Enter options (comma-separated, e.g., --dangerously-skip-permissions) []: "
          options_input = $stdin.gets.chomp
          plan_options = options_input.split(',').map(&:strip).reject(&:empty?) unless options_input.empty?

          print "Enter parameter (use {{issue-number}} for issue number) [/osoba:plan {{issue-number}}]: "
          plan_parameter = $stdin.gets.chomp
          plan_parameter = '/osoba:plan {{issue-number}}' if plan_parameter.empty?
        end

        # Implement phase command
        puts ""
        puts "Implementation phase command:"
        print "Enter command (e.g., claude) [skip]: "
        implement_command = $stdin.gets.chomp
        if implement_command.empty? || implement_command.downcase == 'skip'
          implement_command = nil
        end

        implement_options = []
        implement_parameter = nil
        if implement_command
          print "Enter options (comma-separated, e.g., --dangerously-skip-permissions) []: "
          options_input = $stdin.gets.chomp
          implement_options = options_input.split(',').map(&:strip).reject(&:empty?) unless options_input.empty?

          print "Enter parameter (use {{issue-number}} for issue number) [/osoba:implement {{issue-number}}]: "
          implement_parameter = $stdin.gets.chomp
          implement_parameter = '/osoba:implement {{issue-number}}' if implement_parameter.empty?
        end

        # Create configuration
        config = {
          'github' => {
            'token' => token,
            'repository' => repository,
          },
          'workflow' => {
            'interval' => interval,
            'phase_labels' => {
              'planning' => planning_label,
              'ready' => ready_label,
              'doing' => doing_label,
              'review_requested' => review_label,
            },
          },
        }

        # Add phase configuration if provided
        if plan_command || implement_command
          config['phase'] = {}

          if plan_command
            config['phase']['plan'] = {
              'command' => plan_command,
              'options' => plan_options,
              'parameter' => plan_parameter,
            }
          end

          if implement_command
            config['phase']['implement'] = {
              'command' => implement_command,
              'options' => implement_options,
              'parameter' => implement_parameter,
            }
          end
        end

        # Write configuration file
        config_path.dirname.mkpath
        config_content = <<~YAML
          # soba CLI configuration
          # Generated by: soba init
          # Date: #{Time.now}

          github:
            # GitHub Personal Access Token
            # Can use environment variable: ${GITHUB_TOKEN}
            token: #{config['github']['token']}

            # Target repository (format: owner/repo)
            repository: #{config['github']['repository']}

          workflow:
            # Issue polling interval in seconds
            interval: #{config['workflow']['interval']}

            # Phase labels for tracking issue progress
            phase_labels:
              planning: #{config['workflow']['phase_labels']['planning']}
              ready: #{config['workflow']['phase_labels']['ready']}
              doing: #{config['workflow']['phase_labels']['doing']}
              review_requested: #{config['workflow']['phase_labels']['review_requested']}
        YAML

        # Add phase configuration if present
        if config['phase']
          phase_content = "\n          # Phase command configuration\n          phase:\n"

          if config['phase']['plan']
            phase_content += "            plan:\n"
            phase_content += "              command: #{config['phase']['plan']['command']}\n"
            if config['phase']['plan']['options'].present?
              phase_content += "              options:\n"
              config['phase']['plan']['options'].each do |opt|
                phase_content += "                - #{opt}\n"
              end
            end
            if config['phase']['plan']['parameter']
              phase_content += "              parameter: '#{config['phase']['plan']['parameter']}'\n"
            end
          end

          if config['phase']['implement']
            phase_content += "            implement:\n"
            phase_content += "              command: #{config['phase']['implement']['command']}\n"
            if config['phase']['implement']['options'].present?
              phase_content += "              options:\n"
              config['phase']['implement']['options'].each do |opt|
                phase_content += "                - #{opt}\n"
              end
            end
            if config['phase']['implement']['parameter']
              phase_content += "              parameter: '#{config['phase']['implement']['parameter']}'\n"
            end
          end

          # Remove extra indentation to match YAML structure
          phase_content = phase_content.gsub(/^          /, '')
          config_content += phase_content
        end

        File.write(config_path, config_content)

        puts ""
        puts "✅ Configuration created successfully!"
        puts "📁 Location: #{config_path}"

        # Verify token if environment variable is used
        if token == '${GITHUB_TOKEN}'
          puts ""
          if ENV['GITHUB_TOKEN']
            puts "✅ GITHUB_TOKEN environment variable is set"
          else
            puts "⚠️  GITHUB_TOKEN environment variable is not set"
            puts "   Please set it before running soba commands:"
            puts "   export GITHUB_TOKEN='your-token-here'"
          end
        end

        # Add .soba to .gitignore if needed
        gitignore_path = Pathname.pwd.join('.gitignore')
        if gitignore_path.exist?
          gitignore_content = File.read(gitignore_path)
          unless gitignore_content.include?('.soba')
            puts ""
            print "Add .soba/ to .gitignore? (Y/n): "
            response = $stdin.gets.chomp.downcase
            if response != 'n' && response != 'no'
              File.open(gitignore_path, 'a') do |f|
                f.puts "" unless gitignore_content.end_with?("\n")
                f.puts "# soba configuration directory"
                f.puts ".soba/"
              end
              puts "✅ Added .soba/ to .gitignore"
            end
          end
        end

        puts ""
        puts "🎉 Setup complete! You can now use:"
        puts "   soba config     - View current configuration"
        puts "   soba issue list #{config['github']['repository']} - List repository issues"
      rescue Interrupt
        puts "\n\n❌ Setup cancelled."
        exit 1
      rescue StandardError => e
        puts "\n❌ Error: #{e.message}"
        exit 1
      end

      private

      def detect_github_repository
        return nil unless Dir.exist?('.git')

        # Try to get remote origin URL
        remote_url = `git config --get remote.origin.url 2>/dev/null`.chomp
        return nil if remote_url.empty?

        # Parse GitHub repository from various URL formats
        # https://github.com/owner/repo.git
        # git@github.com:owner/repo.git
        # ssh://git@github.com/owner/repo.git
        case remote_url
        when %r{github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$}
          "#{Regexp.last_match(1)}/#{Regexp.last_match(2)}"
        when %r{^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$}
          "#{Regexp.last_match(1)}/#{Regexp.last_match(2)}"
        else
          nil
        end
      rescue StandardError
        nil
      end
    end
  end
end