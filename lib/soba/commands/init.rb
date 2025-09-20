# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/exclude"
require "active_support/core_ext/object/deep_dup"
require "pathname"
require "yaml"
require "io/console"
require_relative "../infrastructure/github_client"

module Soba
  module Commands
    class Init
      DEFAULT_CONFIG = {
        'github' => {
          'token' => '${GITHUB_TOKEN}',
        },
        'workflow' => {
          'interval' => 20,
          'auto_merge_enabled' => true,
          'closed_issue_cleanup_enabled' => true,
          'closed_issue_cleanup_interval' => 300,
          'tmux_command_delay' => 3,
          'phase_labels' => {
            'todo' => 'soba:todo',
            'queued' => 'soba:queued',
            'planning' => 'soba:planning',
            'ready' => 'soba:ready',
            'doing' => 'soba:doing',
            'review_requested' => 'soba:review-requested',
            'reviewing' => 'soba:reviewing',
            'done' => 'soba:done',
            'requires_changes' => 'soba:requires-changes',
            'revising' => 'soba:revising',
            'merged' => 'soba:merged',
          },
        },
      }.freeze

      LABEL_COLORS = {
        'todo' => '808080',            # Gray
        'queued' => '9370db',          # Medium Purple
        'planning' => '1e90ff',        # Blue
        'ready' => '228b22',           # Green
        'doing' => 'ffd700',           # Yellow
        'review_requested' => 'ff8c00', # Orange
        'reviewing' => 'ff6347',       # Tomato
        'done' => '32cd32',            # Lime Green
        'requires_changes' => 'dc143c', # Crimson
        'revising' => 'ff1493',        # Deep Pink
        'merged' => '6b8e23',          # Olive Drab
        'lgtm' => '00ff00',            # Pure Green
      }.freeze

      LABEL_DESCRIPTIONS = {
        'todo' => 'To-do task waiting to be queued',
        'queued' => 'Queued for processing',
        'planning' => 'Planning phase',
        'ready' => 'Ready for implementation',
        'doing' => 'In progress',
        'review_requested' => 'Review requested',
        'reviewing' => 'Under review',
        'done' => 'Review completed',
        'requires_changes' => 'Changes requested',
        'revising' => 'Revising based on review feedback',
        'merged' => 'PR merged and issue closed',
        'lgtm' => 'PR approved for auto-merge',
      }.freeze

      DEFAULT_PHASE_CONFIG = {
        'plan' => {
          'command' => 'claude',
          'options' => ['--dangerously-skip-permissions'],
          'parameter' => '/soba:plan {{issue-number}}',
        },
        'implement' => {
          'command' => 'claude',
          'options' => ['--dangerously-skip-permissions'],
          'parameter' => '/soba:implement {{issue-number}}',
        },
        'review' => {
          'command' => 'claude',
          'options' => ['--dangerously-skip-permissions'],
          'parameter' => '/soba:review {{issue-number}}',
        },
        'revise' => {
          'command' => 'claude',
          'options' => ['--dangerously-skip-permissions'],
          'parameter' => '/soba:revise {{issue-number}}',
        },
      }.freeze

      def initialize(interactive: false)
        @interactive = interactive
      end

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

        if @interactive
          execute_interactive(config_path)
        else
          execute_non_interactive(config_path)
        end
      rescue Interrupt
        puts "\n\n❌ Setup cancelled."
        raise Soba::CommandError, "Setup cancelled"
      rescue StandardError => e
        puts "\n❌ Error: #{e.message}"
        raise
      end

      private

      def execute_non_interactive(config_path)
        # GitHub repository - auto-detect from git remote
        repository = detect_github_repository

        unless repository
          puts "❌ Error: Cannot detect GitHub repository from git remote."
          puts "   Please run 'soba init --interactive' for manual setup."
          raise Soba::CommandError, "Cannot detect GitHub repository"
        end

        # Create configuration with default values
        config = DEFAULT_CONFIG.deep_dup
        config['github']['repository'] = repository

        # Add default phase configuration
        config['phase'] = DEFAULT_PHASE_CONFIG.deep_dup

        # Write configuration file
        write_config_file(config_path, config)

        puts ""
        puts "✅ Configuration created successfully!"
        puts "📁 Location: #{config_path}"
        puts "📦 Repository: #{repository}"

        check_github_token(token: '${GITHUB_TOKEN}')
        handle_gitignore
        create_github_labels(config)

        puts ""
        puts "🎉 Setup complete! You can now use:"
        puts "   soba config     - View current configuration"
        puts "   soba issue list #{config['github']['repository']} - List repository issues"
      end

      def execute_interactive(config_path)
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

        # Auto-merge configuration
        puts ""
        print "Enable auto-merge for PRs with soba:lgtm label? (y/n) [y]: "
        auto_merge = $stdin.gets.chomp.downcase
        auto_merge = 'y' if auto_merge.empty?
        auto_merge_enabled = auto_merge != 'n'

        # Workflow commands configuration
        puts ""
        puts "Workflow commands configuration (optional):"
        puts "These commands will be executed during each phase"
        puts ""

        # Plan phase command
        puts "Planning phase command:"
        print "Enter command (e.g., claude) [#{DEFAULT_PHASE_CONFIG['plan']['command']}]: "
        plan_command = $stdin.gets.chomp
        plan_command = DEFAULT_PHASE_CONFIG['plan']['command'] if plan_command.empty?
        if plan_command.downcase == 'skip'
          plan_command = nil
        end

        plan_options = []
        plan_parameter = nil
        if plan_command
          default_options = DEFAULT_PHASE_CONFIG['plan']['options'].join(',')
          print "Enter options (comma-separated, e.g., --dangerously-skip-permissions) [#{default_options}]: "
          options_input = $stdin.gets.chomp
          if options_input.empty?
            plan_options = DEFAULT_PHASE_CONFIG['plan']['options']
          else
            plan_options = options_input.split(',').map(&:strip).reject(&:empty?)
          end

          default_param = DEFAULT_PHASE_CONFIG['plan']['parameter']
          print "Enter parameter (use {{issue-number}} for issue number) [#{default_param}]: "
          plan_parameter = $stdin.gets.chomp
          plan_parameter = DEFAULT_PHASE_CONFIG['plan']['parameter'] if plan_parameter.empty?
        end

        # Implement phase command
        puts ""
        puts "Implementation phase command:"
        print "Enter command (e.g., claude) [#{DEFAULT_PHASE_CONFIG['implement']['command']}]: "
        implement_command = $stdin.gets.chomp
        implement_command = DEFAULT_PHASE_CONFIG['implement']['command'] if implement_command.empty?
        if implement_command.downcase == 'skip'
          implement_command = nil
        end

        implement_options = []
        implement_parameter = nil
        if implement_command
          default_options = DEFAULT_PHASE_CONFIG['implement']['options'].join(',')
          print "Enter options (comma-separated, e.g., --dangerously-skip-permissions) [#{default_options}]: "
          options_input = $stdin.gets.chomp
          if options_input.empty?
            implement_options = DEFAULT_PHASE_CONFIG['implement']['options']
          else
            implement_options = options_input.split(',').map(&:strip).reject(&:empty?)
          end

          default_param = DEFAULT_PHASE_CONFIG['implement']['parameter']
          print "Enter parameter (use {{issue-number}} for issue number) [#{default_param}]: "
          implement_parameter = $stdin.gets.chomp
          implement_parameter = DEFAULT_PHASE_CONFIG['implement']['parameter'] if implement_parameter.empty?
        end

        # Review phase command
        puts ""
        puts "Review phase command:"
        print "Enter command (e.g., claude) [#{DEFAULT_PHASE_CONFIG['review']['command']}]: "
        review_command = $stdin.gets.chomp
        review_command = DEFAULT_PHASE_CONFIG['review']['command'] if review_command.empty?
        if review_command.downcase == 'skip'
          review_command = nil
        end

        review_options = []
        review_parameter = nil
        if review_command
          default_options = DEFAULT_PHASE_CONFIG['review']['options'].join(',')
          print "Enter options (comma-separated, e.g., --dangerously-skip-permissions) [#{default_options}]: "
          options_input = $stdin.gets.chomp
          if options_input.empty?
            review_options = DEFAULT_PHASE_CONFIG['review']['options']
          else
            review_options = options_input.split(',').map(&:strip).reject(&:empty?)
          end

          default_param = DEFAULT_PHASE_CONFIG['review']['parameter']
          print "Enter parameter (use {{issue-number}} for issue number) [#{default_param}]: "
          review_parameter = $stdin.gets.chomp
          review_parameter = DEFAULT_PHASE_CONFIG['review']['parameter'] if review_parameter.empty?
        end

        # Create configuration
        config = {
          'github' => {
            'token' => token,
            'repository' => repository,
          },
          'workflow' => {
            'interval' => interval,
            'auto_merge_enabled' => auto_merge_enabled,
            'closed_issue_cleanup_enabled' => true,
            'closed_issue_cleanup_interval' => 300,
            'tmux_command_delay' => 3,
            'phase_labels' => {
              'todo' => 'soba:todo',
              'queued' => 'soba:queued',
              'planning' => planning_label,
              'ready' => ready_label,
              'doing' => doing_label,
              'review_requested' => review_label,
              'reviewing' => 'soba:reviewing',
              'done' => 'soba:done',
              'requires_changes' => 'soba:requires-changes',
              'revising' => 'soba:revising',
              'merged' => 'soba:merged',
            },
          },
        }

        # Add phase configuration if provided
        if plan_command || implement_command || review_command
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

          if review_command
            config['phase']['review'] = {
              'command' => review_command,
              'options' => review_options,
              'parameter' => review_parameter,
            }
          end
        end

        # Write configuration file
        write_config_file(config_path, config)

        puts ""
        puts "✅ Configuration created successfully!"
        puts "📁 Location: #{config_path}"

        check_github_token(token: token)
        handle_gitignore
        create_github_labels(config)

        puts ""
        puts "🎉 Setup complete! You can now use:"
        puts "   soba config     - View current configuration"
        puts "   soba issue list #{config['github']['repository']} - List repository issues"
      end

      def write_config_file(config_path, config)
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

            # Enable automatic merging of PRs with soba:lgtm label
            auto_merge_enabled: #{config['workflow']['auto_merge_enabled']}

            # Enable automatic cleanup of tmux windows for closed issues
            closed_issue_cleanup_enabled: #{config['workflow']['closed_issue_cleanup_enabled']}

            # Cleanup check interval in seconds
            closed_issue_cleanup_interval: #{config['workflow']['closed_issue_cleanup_interval']}

            # Delay (in seconds) before sending commands to new tmux panes/windows
            tmux_command_delay: #{config['workflow']['tmux_command_delay']}

            # Phase labels for tracking issue progress
            phase_labels:
              todo: #{config['workflow']['phase_labels']['todo']}
              queued: #{config['workflow']['phase_labels']['queued']}
              planning: #{config['workflow']['phase_labels']['planning']}
              ready: #{config['workflow']['phase_labels']['ready']}
              doing: #{config['workflow']['phase_labels']['doing']}
              review_requested: #{config['workflow']['phase_labels']['review_requested']}
              reviewing: #{config['workflow']['phase_labels']['reviewing']}
              done: #{config['workflow']['phase_labels']['done']}
              requires_changes: #{config['workflow']['phase_labels']['requires_changes']}
              revising: #{config['workflow']['phase_labels']['revising']}
              merged: #{config['workflow']['phase_labels']['merged']}
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

          if config['phase']['review']
            phase_content += "            review:\n"
            phase_content += "              command: #{config['phase']['review']['command']}\n"
            if config['phase']['review']['options'].present?
              phase_content += "              options:\n"
              config['phase']['review']['options'].each do |opt|
                phase_content += "                - #{opt}\n"
              end
            end
            if config['phase']['review']['parameter']
              phase_content += "              parameter: '#{config['phase']['review']['parameter']}'\n"
            end
          end

          if config['phase']['revise']
            phase_content += "            revise:\n"
            phase_content += "              command: #{config['phase']['revise']['command']}\n"
            if config['phase']['revise']['options'].present?
              phase_content += "              options:\n"
              config['phase']['revise']['options'].each do |opt|
                phase_content += "                - #{opt}\n"
              end
            end
            if config['phase']['revise']['parameter']
              phase_content += "              parameter: '#{config['phase']['revise']['parameter']}'\n"
            end
          end

          # Remove extra indentation to match YAML structure
          phase_content = phase_content.gsub(/^          /, '')
          config_content += phase_content
        end

        File.write(config_path, config_content)
      end

      def check_github_token(token: '${GITHUB_TOKEN}')
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
      end

      def handle_gitignore
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
      end

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

      def create_github_labels(config)
        repository = config['github']['repository']
        phase_labels = config['workflow']['phase_labels']

        # Only ask for confirmation in interactive mode
        if @interactive
          puts ""
          print "Create GitHub labels for workflow phases? (Y/n): "
          response = $stdin.gets
          return unless response
          response = response.chomp.downcase
          if response == 'n' || response == 'no'
            puts "✅ Skipping label creation."
            return
          end
        end

        puts ""
        puts "🏷️  Creating GitHub labels..."

        begin
          # Initialize GitHub client
          github_client = Infrastructure::GitHubClient.new

          # Get existing labels
          existing_labels = github_client.list_labels(repository)
          existing_label_names = existing_labels.map { |label| label[:name] }

          # Create labels for each phase
          created_count = 0
          skipped_count = 0

          # Create phase labels
          phase_labels.each do |phase, label_name|
            if existing_label_names.include?(label_name)
              puts "   ⏩ Label '#{label_name}' already exists, skipping"
              skipped_count += 1
            else
              color = LABEL_COLORS[phase]
              description = LABEL_DESCRIPTIONS[phase]

              result = github_client.create_label(repository, label_name, color, description)
              if result
                puts "   ✅ Label '#{label_name}' created"
                created_count += 1
              else
                puts "   ⚠️  Label '#{label_name}' could not be created (may already exist)"
                skipped_count += 1
              end
            end
          end

          # Create additional PR label
          additional_labels = [
            { name: 'soba:lgtm', phase: 'lgtm' },
          ]

          additional_labels.each do |label_info|
            label_name = label_info[:name]
            if existing_label_names.include?(label_name)
              puts "   ⏩ Label '#{label_name}' already exists, skipping"
              skipped_count += 1
            else
              color = LABEL_COLORS[label_info[:phase]]
              description = LABEL_DESCRIPTIONS[label_info[:phase]]

              result = github_client.create_label(repository, label_name, color, description)
              if result
                puts "   ✅ Label '#{label_name}' created"
                created_count += 1
              else
                puts "   ⚠️  Label '#{label_name}' could not be created (may already exist)"
                skipped_count += 1
              end
            end
          end

          puts ""
          puts "✅ Label creation complete: #{created_count} created, #{skipped_count} skipped"
        rescue Infrastructure::AuthenticationError => e
          puts "   ❌ Authentication failed: #{e.message}"
          puts "   Please ensure your GitHub token has 'repo' permission"
        rescue Infrastructure::GitHubClientError => e
          puts "   ❌ Failed to create labels: #{e.message}"
          puts "   Please check your repository permissions"
        rescue StandardError => e
          puts "   ❌ Unexpected error: #{e.message}"
        end
      end
    end
  end
end