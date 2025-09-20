# frozen_string_literal: true

require "spec_helper"
require "soba/commands/init"
require "tmpdir"
require "stringio"
require "soba/infrastructure/github_client"

RSpec.describe Soba::Commands::Init do
  let(:command) { described_class.new(interactive: true) }

  # Helper method to build interactive input sequence
  def build_interactive_input(options = {})
    inputs = []

    # Repository
    inputs << (options[:repository] || "douhashi/soba")

    # GitHub token option (1 or 2)
    inputs << (options[:token_option] || "1")

    # GitHub token (only if option 2)
    # This is handled by noecho, not regular gets

    # Polling interval
    inputs << (options[:interval] || "20")

    # Phase labels
    inputs << (options[:planning_label] || "")
    inputs << (options[:ready_label] || "")
    inputs << (options[:doing_label] || "")
    inputs << (options[:review_label] || "")

    # Auto-merge
    inputs << (options[:auto_merge] || "")

    # Slack notifications (NEW)
    inputs << (options[:slack_enabled] || "n")

    # Slack webhook option (only if slack enabled)
    if options[:slack_enabled] == "y"
      inputs << (options[:slack_option] || "1")
    end

    # Workflow commands
    plan_cmd = options.fetch(:plan_command, "skip")
    inputs << plan_cmd

    if plan_cmd != "skip"
      inputs << (options[:plan_options] || "")
      inputs << (options[:plan_parameter] || "")
    end

    implement_cmd = options.fetch(:implement_command, "skip")
    inputs << implement_cmd

    if implement_cmd != "skip"
      inputs << (options[:implement_options] || "")
      inputs << (options[:implement_parameter] || "")
    end

    review_cmd = options.fetch(:review_command, "skip")
    inputs << review_cmd

    if review_cmd != "skip"
      inputs << (options[:review_options] || "")
      inputs << (options[:review_parameter] || "")
    end

    # Label creation prompt (if interactive)
    inputs << (options[:create_labels] || "") if options[:with_label_prompt]

    # Gitignore prompt
    inputs << (options[:add_gitignore] || "") if options[:with_gitignore_prompt]

    StringIO.new(inputs.join("\n") + "\n")
  end

  describe "#execute with interactive mode" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:config_path) { Pathname.new(temp_dir).join('.soba', 'config.yml') }

    before do
      allow(Pathname).to receive(:pwd).and_return(Pathname.new(temp_dir))
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context "when config file does not exist" do
      it "creates a new configuration file" do
        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['phase_labels']['todo']).to eq('soba:todo')
        expect(config['workflow']['phase_labels']['queued']).to eq('soba:queued')
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')
        expect(config['workflow']['phase_labels']['reviewing']).to eq('soba:reviewing')
        expect(config['workflow']['phase_labels']['done']).to eq('soba:done')
        expect(config['workflow']['phase_labels']['requires_changes']).to eq('soba:requires-changes')
        expect(config['workflow']['phase_labels']['revising']).to eq('soba:revising')
        expect(config['workflow']['phase_labels']['merged']).to eq('soba:merged')
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']).to be_nil
      end

      it "accepts direct token input" do
        input = build_interactive_input(token_option: "2", interval: "30")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(StringIO.new("secret_token\n"))

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('secret_token')
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
      end

      it "accepts custom phase labels" do
        input = build_interactive_input(
          planning_label: "planning",
          ready_label: "ready",
          doing_label: "doing",
          review_label: "review"
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['phase_labels']['todo']).to eq('soba:todo')
        expect(config['workflow']['phase_labels']['queued']).to eq('soba:queued')
        expect(config['workflow']['phase_labels']['planning']).to eq('planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('review')
        expect(config['workflow']['phase_labels']['reviewing']).to eq('soba:reviewing')
        expect(config['workflow']['phase_labels']['done']).to eq('soba:done')
        expect(config['workflow']['phase_labels']['requires_changes']).to eq('soba:requires-changes')
        expect(config['workflow']['phase_labels']['revising']).to eq('soba:revising')
        expect(config['workflow']['phase_labels']['merged']).to eq('soba:merged')
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
      end

      it "accepts workflow phase commands" do
        input = build_interactive_input(
          plan_command: "claude",
          plan_options: "--dangerously-skip-permissions",
          plan_parameter: "/soba:plan {{issue-number}}",
          implement_command: "claude",
          implement_options: "--dangerously-skip-permissions",
          implement_parameter: "/soba:implement {{issue-number}}",
          review_command: "claude",
          review_options: "--dangerously-skip-permissions",
          review_parameter: "/soba:review {{issue-number}}"
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')
      end

      it "shows default values in prompts and applies them on empty input" do
        input = build_interactive_input(
          plan_command: "",
          implement_command: "",
          review_command: ""
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        # Check that prompts show default values
        expect { command.execute }.to output(
          /\[claude\].*\[--dangerously-skip-permissions\].*\[\/soba:plan {{issue-number}}\].*\[claude\].*\[--dangerously-skip-permissions\].*\[\/soba:implement {{issue-number}}\].*\[claude\].*\[--dangerously-skip-permissions\].*\[\/soba:review {{issue-number}}\]/m
        ).to_stdout

        # Check that config applies default values when Enter is pressed
        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')
      end

      it "applies default values for phase commands when empty input is given" do
        # すべてのプロンプトで空入力（Enterキー）を入力
        input = build_interactive_input(
          plan_command: "",
          implement_command: "",
          review_command: ""
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        # phase設定が作成され、デフォルト値が適用されていることを確認
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']).not_to be_nil
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')
      end

      it "allows partial customization with some default values" do
        # plan commandはカスタマイズ、他はデフォルト値を使用
        input = build_interactive_input(
          plan_command: "custom-claude",
          implement_command: "",
          review_command: ""
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']['plan']['command']).to eq('custom-claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')
      end

      context "with label creation" do
        let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
        let(:repository) { "douhashi/soba" }

        before do
          allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
        end

        it "creates labels after configuration file is created" do
          input = build_interactive_input(repository: repository, with_label_prompt: true, create_labels: "y")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Expect label creation calls
          expect(github_client).to receive(:list_labels).with(repository).and_return([])
          expect(github_client).to receive(:create_label).
            with(repository, "soba:todo", "808080", "To-do task waiting to be queued").
            and_return({ name: "soba:todo", color: "808080" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:queued", "9370db", "Queued for processing").
            and_return({ name: "soba:queued", color: "9370db" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:planning", "1e90ff", "Planning phase").
            and_return({ name: "soba:planning", color: "1e90ff" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:ready", "228b22", "Ready for implementation").
            and_return({ name: "soba:ready", color: "228b22" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:doing", "ffd700", "In progress").
            and_return({ name: "soba:doing", color: "ffd700" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:review-requested", "ff8c00", "Review requested").
            and_return({ name: "soba:review-requested", color: "ff8c00" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:reviewing", "ff6347", "Under review").
            and_return({ name: "soba:reviewing", color: "ff6347" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:done", "32cd32", "Review completed").
            and_return({ name: "soba:done", color: "32cd32" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:requires-changes", "dc143c", "Changes requested").
            and_return({ name: "soba:requires-changes", color: "dc143c" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:revising", "ff1493", "Revising based on review feedback").
            and_return({ name: "soba:revising", color: "ff1493" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:merged", "6b8e23", "PR merged and issue closed").
            and_return({ name: "soba:merged", color: "6b8e23" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:lgtm", "00ff00", "PR approved for auto-merge").
            and_return({ name: "soba:lgtm", color: "00ff00" })

          expect { command.execute }.to output(/Creating GitHub labels.*Label creation complete: 12 created, 0 skipped/m).to_stdout

          expect(config_path).to exist
        end

        it "skips label creation when user declines" do
          input = build_interactive_input(repository: repository, with_label_prompt: true, create_labels: "n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Should not call any label methods
          expect(github_client).not_to receive(:list_labels)
          expect(github_client).not_to receive(:create_label)

          expect { command.execute }.to output(/Skipping label creation/).to_stdout
        end

        it "skips existing labels" do
          input = build_interactive_input(repository: repository, with_label_prompt: true, create_labels: "y")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Return existing labels
          existing_labels = [
            { name: "soba:planning", color: "1e90ff" },
            { name: "soba:doing", color: "ffd700" },
          ]
          expect(github_client).to receive(:list_labels).with(repository).and_return(existing_labels)

          # Only create missing labels
          expect(github_client).to receive(:create_label).
            with(repository, "soba:todo", "808080", "To-do task waiting to be queued").
            and_return({ name: "soba:todo", color: "808080" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:queued", "9370db", "Queued for processing").
            and_return({ name: "soba:queued", color: "9370db" })
          expect(github_client).not_to receive(:create_label).
            with(repository, "soba:planning", anything, anything)
          expect(github_client).to receive(:create_label).
            with(repository, "soba:ready", "228b22", "Ready for implementation").
            and_return({ name: "soba:ready", color: "228b22" })
          expect(github_client).not_to receive(:create_label).
            with(repository, "soba:doing", anything, anything)
          expect(github_client).to receive(:create_label).
            with(repository, "soba:review-requested", "ff8c00", "Review requested").
            and_return({ name: "soba:review-requested", color: "ff8c00" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:reviewing", "ff6347", "Under review").
            and_return({ name: "soba:reviewing", color: "ff6347" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:done", "32cd32", "Review completed").
            and_return({ name: "soba:done", color: "32cd32" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:requires-changes", "dc143c", "Changes requested").
            and_return({ name: "soba:requires-changes", color: "dc143c" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:revising", "ff1493", "Revising based on review feedback").
            and_return({ name: "soba:revising", color: "ff1493" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:merged", "6b8e23", "PR merged and issue closed").
            and_return({ name: "soba:merged", color: "6b8e23" })
          expect(github_client).to receive(:create_label).
            with(repository, "soba:lgtm", "00ff00", "PR approved for auto-merge").
            and_return({ name: "soba:lgtm", color: "00ff00" })

          expect { command.execute }.to output(/Label creation complete: 10 created, 2 skipped/m).to_stdout
        end

        it "handles label creation errors gracefully" do
          input = build_interactive_input(repository: repository, with_label_prompt: true, create_labels: "y")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect(github_client).to receive(:list_labels).with(repository).and_return([])
          expect(github_client).to receive(:create_label).
            with(repository, "soba:todo", "808080", "To-do task waiting to be queued").
            and_raise(Soba::Infrastructure::GitHubClientError, "Insufficient permissions")

          expect { command.execute }.to output(/Creating GitHub labels/).to_stdout

          # Config should still be created
          expect(config_path).to exist
        end
      end

      it "uses correct default values for workflow phase commands" do
        input = build_interactive_input(
          plan_command: "claude",
          plan_options: "--dangerously-skip-permissions",
          plan_parameter: "",
          implement_command: "claude",
          implement_options: "--dangerously-skip-permissions",
          implement_parameter: "",
          review_command: "claude",
          review_options: "--dangerously-skip-permissions",
          review_parameter: ""
        )
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')
      end

      it "skips workflow commands when skip is entered" do
        input = build_interactive_input # defaults to skip for commands
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['phase']).to be_nil
      end

      context "with Slack notification configuration" do
        it "configures Slack notifications when enabled" do
          input = build_interactive_input(slack_enabled: "y", slack_option: "1")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect { command.execute }.to output(/Slack notifications?/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['slack']).not_to be_nil
          expect(config['slack']['webhook_url']).to eq('${SLACK_WEBHOOK_URL}')
          expect(config['slack']['notifications_enabled']).to eq(true)
        end

        it "allows direct Slack webhook URL input" do
          input = build_interactive_input(slack_enabled: "y", slack_option: "2")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(StringIO.new("https://hooks.slack.com/services/TEST\n"))

          expect { command.execute }.to output(/Slack notifications?/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['slack']).not_to be_nil
          expect(config['slack']['webhook_url']).to eq('https://hooks.slack.com/services/TEST')
          expect(config['slack']['notifications_enabled']).to eq(true)
        end

        it "disables Slack notifications when declined" do
          input = build_interactive_input(slack_enabled: "n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect { command.execute }.to output(/Configuration created successfully/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['slack']).not_to be_nil
          expect(config['slack']['webhook_url']).to eq('${SLACK_WEBHOOK_URL}')
          expect(config['slack']['notifications_enabled']).to eq(false)
        end

        it "checks for SLACK_WEBHOOK_URL environment variable when configured" do
          allow(ENV).to receive(:[]).and_return(nil)
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
          allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return('https://hooks.slack.com/services/ENV')
          input = build_interactive_input(slack_enabled: "y", slack_option: "1")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/SLACK_WEBHOOK_URL environment variable is set/).to_stdout
        end

        it "warns when SLACK_WEBHOOK_URL is not set" do
          allow(ENV).to receive(:[]).and_return(nil)
          allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
          allow(ENV).to receive(:[]).with('SLACK_WEBHOOK_URL').and_return(nil)
          input = build_interactive_input(slack_enabled: "y", slack_option: "1")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/SLACK_WEBHOOK_URL environment variable is not set/).to_stdout
        end
      end

      it "validates repository format" do
        inputs = []
        inputs << "invalid" # Invalid repository format
        inputs += build_interactive_input.string.split("\n") # Rest of the inputs
        input = StringIO.new(inputs.join("\n") + "\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Invalid format/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
      end

      it "uses default values when empty input" do
        # Mock GitHubTokenProvider to ensure consistent behavior
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:gh_available?).and_return(false)
        allow(token_provider).to receive(:detect_best_method).and_return(nil)

        input = build_interactive_input(token_option: "", interval: "")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['phase_labels']['todo']).to eq('soba:todo')
        expect(config['workflow']['phase_labels']['queued']).to eq('soba:queued')
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')
        expect(config['workflow']['phase_labels']['reviewing']).to eq('soba:reviewing')
        expect(config['workflow']['phase_labels']['done']).to eq('soba:done')
        expect(config['workflow']['phase_labels']['requires_changes']).to eq('soba:requires-changes')
        expect(config['workflow']['phase_labels']['revising']).to eq('soba:revising')
        expect(config['workflow']['phase_labels']['merged']).to eq('soba:merged')
        expect(config['workflow']['tmux_command_delay']).to eq(3)
      end

      context "with git repository detection" do
        it "detects GitHub repository from git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = build_interactive_input(repository: "")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[user\/repo\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('user/repo')
          expect(config['workflow']['auto_merge_enabled']).to eq(true)
        end

        it "handles SSH format git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("git@github.com:owner/project.git\n")

          input = build_interactive_input(repository: "")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[owner\/project\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('owner/project')
          expect(config['workflow']['auto_merge_enabled']).to eq(true)
        end

        it "allows manual override of detected repository" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = build_interactive_input(repository: "different/repo")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[user\/repo\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('different/repo')
          expect(config['workflow']['auto_merge_enabled']).to eq(true)
        end
      end
    end

    context "when config file already exists" do
      before do
        config_path.dirname.mkpath
        File.write(config_path, "existing: config")
      end

      it "asks for confirmation before overwriting" do
        inputs = ["y"] # Overwrite confirmation
        inputs += build_interactive_input.string.split("\n")
        input = StringIO.new(inputs.join("\n") + "\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(
          /already exists.*Configuration created successfully/m
        ).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']).not_to be_nil
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
      end

      it "does not overwrite when user declines" do
        input = StringIO.new("n\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Configuration unchanged/).to_stdout

        content = File.read(config_path)
        expect(content).to eq("existing: config")
      end
    end

    context "with Claude template deployment" do
      it "deploys Claude command templates during initialization" do
        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        # Check that Claude command template files are created
        claude_dir = Pathname.new(temp_dir).join('.claude', 'commands', 'soba')
        expect(claude_dir).to exist
        expect(claude_dir.join('plan.md')).to exist
        expect(claude_dir.join('implement.md')).to exist
        expect(claude_dir.join('review.md')).to exist
        expect(claude_dir.join('revise.md')).to exist
      end

      context "when Claude command files already exist" do
        before do
          claude_dir = Pathname.new(temp_dir).join('.claude', 'commands', 'soba')
          claude_dir.mkpath
          File.write(claude_dir.join('plan.md'), "existing content")
        end

        it "prompts for confirmation before overwriting" do
          # Create a custom input that includes responses for Claude template prompts
          base_inputs = build_interactive_input.string.split("\n")
          template_response = "y" # Response for overwriting the plan.md template

          # Build custom input including template response
          all_inputs = base_inputs + [template_response]
          input = StringIO.new(all_inputs.join("\n") + "\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect { command.execute }.to output(/Claude command template already exists.*Overwriting/m).to_stdout

          # Verify file was overwritten
          plan_content = File.read(Pathname.new(temp_dir).join('.claude', 'commands', 'soba', 'plan.md'))
          expect(plan_content).not_to eq("existing content")
        end

        it "skips overwriting when user declines" do
          # Create a custom input that includes responses for Claude template prompts
          base_inputs = build_interactive_input.string.split("\n")
          template_response = "n" # Response for keeping the existing plan.md template

          # Build custom input including template response
          all_inputs = base_inputs + [template_response]
          input = StringIO.new(all_inputs.join("\n") + "\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect { command.execute }.to output(/Claude command template already exists.*Keeping existing/m).to_stdout

          # Verify file was not overwritten
          plan_content = File.read(Pathname.new(temp_dir).join('.claude', 'commands', 'soba', 'plan.md'))
          expect(plan_content).to eq("existing content")
        end
      end
    end

    context "with .gitignore handling" do
      let(:gitignore_path) { Pathname.new(temp_dir).join('.gitignore') }

      before do
        File.write(gitignore_path, "*.log\n")
      end

      it "adds .soba to .gitignore when requested" do
        input = build_interactive_input(with_gitignore_prompt: true, add_gitignore: "y")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Added .soba\/ to .gitignore/).to_stdout

        gitignore_content = File.read(gitignore_path)
        expect(gitignore_content).to include('.soba/')
      end

      it "does not add .soba when already present" do
        File.write(gitignore_path, "*.log\n.soba/\n")
        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.not_to output(/Add .soba\/ to .gitignore/).to_stdout
      end
    end

    context "with environment variable detection" do
      it "detects when GITHUB_TOKEN is set" do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('test_token')
        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is set/).to_stdout
      end

      it "warns when GITHUB_TOKEN is not set" do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is not set/).to_stdout
      end
    end

    context "with GitHub auth method detection" do
      it "detects when gh command is available" do
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:gh_available?).and_return(true)
        allow(token_provider).to receive(:detect_best_method).and_return('gh')

        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/gh command is available/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['auth_method']).to eq('gh')
      end

      it "detects when gh command is not available" do
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:gh_available?).and_return(false)
        allow(token_provider).to receive(:detect_best_method).and_return('env')

        input = build_interactive_input
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Using environment variable/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['auth_method']).to eq('env')
      end

      it "prompts for auth method choice in interactive mode" do
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:gh_available?).and_return(true)

        # Add auth method selection to input
        inputs = []
        inputs << "douhashi/soba" # repository
        inputs << "3" # Option 3: Use gh command
        inputs << "20" # interval
        # ... rest of inputs
        inputs << "" # planning_label
        inputs << "" # ready_label
        inputs << "" # doing_label
        inputs << "" # review_label
        inputs << "" # auto_merge
        inputs << "n" # slack
        inputs << "skip" # plan_command
        inputs << "skip" # implement_command
        inputs << "skip" # review_command

        input = StringIO.new(inputs.join("\n") + "\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Use gh command authentication/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['auth_method']).to eq('gh')
        expect(config['github']['token']).to be_nil
      end
    end

    context "error handling" do
      it "handles interrupt gracefully" do
        allow($stdin).to receive(:gets).and_raise(Interrupt)

        expect { command.execute }.to raise_error(Soba::CommandError, /Setup cancelled/)
      end
    end
  end

  describe "#execute with non-interactive mode (default)" do
    let(:command) { described_class.new(interactive: false) }
    let(:temp_dir) { Dir.mktmpdir }
    let(:config_path) { Pathname.new(temp_dir).join('.soba', 'config.yml') }

    before do
      allow(Pathname).to receive(:pwd).and_return(Pathname.new(temp_dir))
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context "when config file does not exist" do
      it "creates a configuration file with default values including phase configuration" do
        # Mock GitHubTokenProvider to ensure consistent behavior
        token_provider = instance_double(Soba::Infrastructure::GitHubTokenProvider)
        allow(Soba::Infrastructure::GitHubTokenProvider).to receive(:new).and_return(token_provider)
        allow(token_provider).to receive(:detect_best_method).and_return(nil)

        allow(Dir).to receive(:exist?).with('.git').and_return(true)
        allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/douhashi/soba.git\n")

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['auto_merge_enabled']).to eq(true)
        expect(config['workflow']['phase_labels']['todo']).to eq('soba:todo')
        expect(config['workflow']['phase_labels']['queued']).to eq('soba:queued')
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')
        expect(config['workflow']['phase_labels']['reviewing']).to eq('soba:reviewing')
        expect(config['workflow']['phase_labels']['done']).to eq('soba:done')
        expect(config['workflow']['phase_labels']['requires_changes']).to eq('soba:requires-changes')
        expect(config['workflow']['phase_labels']['revising']).to eq('soba:revising')
        expect(config['workflow']['phase_labels']['merged']).to eq('soba:merged')
        expect(config['workflow']['closed_issue_cleanup_enabled']).to eq(true)
        expect(config['workflow']['closed_issue_cleanup_interval']).to eq(300)
        expect(config['workflow']['tmux_command_delay']).to eq(3)

        # Slack configuration should be present with default values
        expect(config['slack']).not_to be_nil
        expect(config['slack']['webhook_url']).to eq('${SLACK_WEBHOOK_URL}')
        expect(config['slack']['notifications_enabled']).to eq(false)

        # Phase configuration should be present with default values
        expect(config['phase']).not_to be_nil
        expect(config['phase']['plan']).not_to be_nil
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')

        expect(config['phase']['implement']).not_to be_nil
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')

        expect(config['phase']['review']).not_to be_nil
        expect(config['phase']['review']['command']).to eq('claude')
        expect(config['phase']['review']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['review']['parameter']).to eq('/soba:review {{issue-number}}')

        expect(config['phase']['revise']).not_to be_nil
        expect(config['phase']['revise']['command']).to eq('claude')
        expect(config['phase']['revise']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['revise']['parameter']).to eq('/soba:revise {{issue-number}}')
        expect(config['workflow']['tmux_command_delay']).to eq(3)
      end

      it "fails when GitHub repository cannot be detected" do
        allow(Dir).to receive(:exist?).with('.git').and_return(false)

        expect { command.execute }.to raise_error(Soba::CommandError, /Cannot detect GitHub repository/)
      end
    end

    context "when config file already exists" do
      before do
        config_path.dirname.mkpath
        File.write(config_path, "existing: config")
      end

      it "asks for confirmation before overwriting" do
        allow(Dir).to receive(:exist?).with('.git').and_return(true)
        allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/douhashi/soba.git\n")

        input = StringIO.new("y\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/already exists.*Configuration created successfully/m).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']).not_to be_nil
      end

      it "does not overwrite when user declines" do
        input = StringIO.new("n\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Configuration unchanged/).to_stdout

        content = File.read(config_path)
        expect(content).to eq("existing: config")
      end
    end

    context "with Claude template deployment" do
      it "deploys Claude command templates during non-interactive initialization" do
        allow(Dir).to receive(:exist?).with('.git').and_return(true)
        allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/douhashi/soba.git\n")

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        # Check that Claude command template files are created
        claude_dir = Pathname.new(temp_dir).join('.claude', 'commands', 'soba')
        expect(claude_dir).to exist
        expect(claude_dir.join('plan.md')).to exist
        expect(claude_dir.join('implement.md')).to exist
        expect(claude_dir.join('review.md')).to exist
        expect(claude_dir.join('revise.md')).to exist
      end
    end

    context "with .gitignore handling" do
      let(:gitignore_path) { Pathname.new(temp_dir).join('.gitignore') }

      before do
        File.write(gitignore_path, "*.log\n")
      end

      it "adds .soba to .gitignore when requested in non-interactive mode" do
        allow(Dir).to receive(:exist?).with('.git').and_return(true)
        allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/douhashi/soba.git\n")

        input = StringIO.new("y\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Added .soba\/ to .gitignore/).to_stdout

        gitignore_content = File.read(gitignore_path)
        expect(gitignore_content).to include('.soba/')
      end
    end
  end
end