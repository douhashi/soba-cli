# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/exclude"
require "active_support/core_ext/object/deep_dup"
require "pathname"
require "yaml"
require "io/console"
require_relative "../infrastructure/github_client"
require_relative "../infrastructure/github_token_provider"

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
        'slack' => {
          'webhook_url' => '${SLACK_WEBHOOK_URL}',
          'notifications_enabled' => false,
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

        # Detect best authentication method
        token_provider = Soba::Infrastructure::GitHubTokenProvider.new
        detected_method = token_provider.detect_best_method

        # Create configuration with default values
        config = DEFAULT_CONFIG.deep_dup
        config['github']['repository'] = repository

        # Set authentication based on detection
        if detected_method == 'gh'
          config['github']['auth_method'] = 'gh'
          config['github'].delete('token')
          puts "✅ Using gh command authentication (detected)"
        elsif detected_method == 'env'
          config['github']['auth_method'] = 'env'
          config['github']['token'] = '${GITHUB_TOKEN}'
          puts "✅ Using environment variable authentication"
        else
          # Keep default token field for backward compatibility
          config['github']['token'] = '${GITHUB_TOKEN}'
          puts "⚠️  No authentication method detected. Please configure manually."
        end

        # Add default phase configuration
        config['phase'] = DEFAULT_PHASE_CONFIG.deep_dup

        # Slack configuration is already included in DEFAULT_CONFIG

        # Write configuration file
        write_config_file(config_path, config)

        puts ""
        puts "✅ Configuration created successfully!"
        puts "📁 Location: #{config_path}"
        puts "📦 Repository: #{repository}"

        check_github_token(token: '${GITHUB_TOKEN}')
        check_slack_webhook_url(config: config)
        deploy_claude_templates
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

        # GitHub authentication detection
        puts ""
        token_provider = Soba::Infrastructure::GitHubTokenProvider.new
        gh_available = token_provider.gh_available?

        if gh_available
          puts "✅ gh command is available and authenticated"
        elsif ENV['GITHUB_TOKEN']
          puts "✅ GITHUB_TOKEN environment variable is set"
        else
          puts "⚠️  Neither gh command nor GITHUB_TOKEN environment variable is available"
        end

        # GitHub token setup
        puts ""
        puts "GitHub authentication setup:"

        auth_method = nil
        token = nil

        if gh_available
          puts "  1. Use environment variable ${GITHUB_TOKEN}"
          puts "  2. Enter token directly (will be visible in config file)"
          puts "  3. Use gh command authentication (detected)"
          print "Choose option (1-3) [3]: "
          token_option = $stdin.gets.chomp
          token_option = '3' if token_option.empty?

          case token_option
          when '2'
            print "Enter GitHub token: "
            # Hide input for security
            token = $stdin.noecho(&:gets).chomp.tap { puts }
            auth_method = nil
          when '3'
            auth_method = 'gh'
            token = nil
          else
            token = '${GITHUB_TOKEN}'
            auth_method = 'env'
          end
        else
          puts "  1. Use environment variable ${GITHUB_TOKEN} (recommended)"
          puts "  2. Enter token directly (will be visible in config file)"
          print "Choose option (1-2) [1]: "
          token_option = $stdin.gets.chomp
          token_option = '1' if token_option.empty?

          if token_option == '2'
            print "Enter GitHub token: "
            # Hide input for security
            token = $stdin.noecho(&:gets).chomp.tap { puts }
            auth_method = nil
          else
            token = '${GITHUB_TOKEN}'
            auth_method = 'env'
          end
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

        # Slack notification configuration
        puts ""
        print "Enable Slack notifications for phase starts? (y/N): "
        slack_enabled = $stdin.gets.chomp.downcase
        slack_enabled = 'n' if slack_enabled.empty?
        slack_notifications_enabled = slack_enabled == 'y'

        slack_webhook_url = '${SLACK_WEBHOOK_URL}'
        if slack_notifications_enabled
          puts "Slack Webhook URL setup:"
          puts "  1. Use environment variable ${SLACK_WEBHOOK_URL} (recommended)"
          puts "  2. Enter webhook URL directly (will be visible in config file)"
          print "Choose option (1-2) [1]: "
          slack_option = $stdin.gets.chomp
          slack_option = '1' if slack_option.empty?

          if slack_option == '2'
            print "Enter Slack webhook URL: "
            # Hide input for security
            slack_webhook_url = $stdin.noecho(&:gets).chomp.tap { puts }
          end
        end

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
          'slack' => {
            'webhook_url' => slack_webhook_url,
            'notifications_enabled' => slack_notifications_enabled,
          },
        }

        # Add token/auth_method based on selection
        if auth_method
          config['github']['auth_method'] = auth_method
          # For env auth method, we still need the token field
          if auth_method == 'env' || token
            config['github']['token'] = token
          end
        else
          config['github']['token'] = token
        end

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
        check_slack_webhook_url(config: config)
        deploy_claude_templates
        handle_gitignore
        create_github_labels(config)

        puts ""
        puts "🎉 Setup complete! You can now use:"
        puts "   soba config     - View current configuration"
        puts "   soba issue list #{config['github']['repository']} - List repository issues"
      end

      def write_config_file(config_path, config)
        config_path.dirname.mkpath
        # Build github section with optional auth_method
        github_section = "  github:\n"

        if config['github']['auth_method']
          github_section += "    # Authentication method (gh, env, or null)\n"
          github_section += "    auth_method: #{config['github']['auth_method']}\n\n"
        end

        if config['github']['token']
          github_section += "    # GitHub Personal Access Token\n"
          github_section += "    # Can use environment variable: ${GITHUB_TOKEN}\n"
          github_section += "    token: #{config['github']['token']}\n\n"
        end

        github_section += "    # Target repository (format: owner/repo)\n"
        github_section += "    repository: #{config['github']['repository']}\n"

        config_content = <<~YAML
          # soba CLI configuration
          # Generated by: soba init
          # Date: #{Time.now}

        #{github_section.chomp}

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

          # Slack notification configuration
          slack:
            # Slack Webhook URL for notifications
            # Can use environment variable: ${SLACK_WEBHOOK_URL}
            webhook_url: #{config['slack']['webhook_url']}

            # Enable Slack notifications for phase starts
            notifications_enabled: #{config['slack']['notifications_enabled']}
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

      def check_slack_webhook_url(config:)
        # Verify Slack webhook URL if environment variable is used and notifications are enabled
        if config['slack'] && config['slack']['notifications_enabled']
          webhook_url = config['slack']['webhook_url']
          if webhook_url == '${SLACK_WEBHOOK_URL}'
            puts ""
            if ENV['SLACK_WEBHOOK_URL']
              puts "✅ SLACK_WEBHOOK_URL environment variable is set"
            else
              puts "⚠️  SLACK_WEBHOOK_URL environment variable is not set"
              puts "   Slack notifications are enabled but webhook URL is missing."
              puts "   Please set it before running soba commands:"
              puts "   export SLACK_WEBHOOK_URL='your-webhook-url-here'"
            end
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

      def deploy_claude_templates
        # Deploy Claude command templates to .claude/commands/soba/
        claude_dir = Pathname.pwd.join('.claude', 'commands', 'soba')
        template_dir = Pathname.new(__dir__).join('..', 'templates', 'claude_commands')

        # Create directory if it doesn't exist
        claude_dir.mkpath

        # List of template files to deploy
        template_files = ['plan.md', 'implement.md', 'review.md', 'revise.md']

        template_files.each do |filename|
          source_file = template_dir.join(filename)
          target_file = claude_dir.join(filename)

          # Check if file already exists
          if target_file.exist?
            if @interactive
              puts ""
              puts "⚠️  Claude command template already exists: #{target_file.relative_path_from(Pathname.pwd)}"
              print "Do you want to overwrite it? (y/N): "
              response = $stdin.gets
              next unless response # Skip if no response
              response = response.chomp.downcase
              if response != 'y' && response != 'yes'
                puts "✅ Keeping existing template: #{filename}"
                next
              else
                puts "✅ Overwriting template: #{filename}"
              end
            end
          end

          # Copy the template file
          FileUtils.cp(source_file, target_file)
          Soba.logger.debug "Deployed Claude template: #{filename}"
        end

        puts ""
        puts "✅ Claude command templates deployed to .claude/commands/soba/"
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
              Soba.logger.debug "Label '#{label_name}' already exists, skipping"
              skipped_count += 1
            else
              color = LABEL_COLORS[phase]
              description = LABEL_DESCRIPTIONS[phase]

              result = github_client.create_label(repository, label_name, color, description)
              if result
                Soba.logger.info "Label '#{label_name}' created"
                created_count += 1
              else
                Soba.logger.warn "Label '#{label_name}' could not be created (may already exist)"
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
              Soba.logger.debug "Label '#{label_name}' already exists, skipping"
              skipped_count += 1
            else
              color = LABEL_COLORS[label_info[:phase]]
              description = LABEL_DESCRIPTIONS[label_info[:phase]]

              result = github_client.create_label(repository, label_name, color, description)
              if result
                Soba.logger.info "Label '#{label_name}' created"
                created_count += 1
              else
                Soba.logger.warn "Label '#{label_name}' could not be created (may already exist)"
                skipped_count += 1
              end
            end
          end

          puts ""
          puts "✅ Label creation complete: #{created_count} created, #{skipped_count} skipped"
        rescue Infrastructure::AuthenticationError => e
          Soba.logger.error "Authentication failed: #{e.message}"
          Soba.logger.error "Please ensure your GitHub token has 'repo' permission"
        rescue Infrastructure::GitHubClientError => e
          Soba.logger.error "Failed to create labels: #{e.message}"
          Soba.logger.error "Please check your repository permissions"
        rescue StandardError => e
          Soba.logger.error "Unexpected error: #{e.message}"
        end
      end
    end
  end
end