# frozen_string_literal: true

require "spec_helper"
require "soba/commands/init"
require "tmpdir"
require "stringio"
require "soba/infrastructure/github_client"

RSpec.describe Soba::Commands::Init do
  let(:command) { described_class.new(interactive: true) }

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
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')
        expect(config['phase']).to be_nil
      end

      it "accepts direct token input" do
        input = StringIO.new("douhashi/soba\n2\n30\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(StringIO.new("secret_token\n"))

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('secret_token')
      end

      it "accepts custom phase labels" do
        input = StringIO.new("douhashi/soba\n1\n20\nplanning\nready\ndoing\nreview\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['workflow']['phase_labels']['planning']).to eq('planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('review')
      end

      it "accepts workflow phase commands" do
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nclaude\n--dangerously-skip-permissions\n/soba:plan {{issue-number}}\nclaude\n--dangerously-skip-permissions\n/soba:implement {{issue-number}}\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
      end

      it "shows default values in prompts and applies them on empty input" do
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\n\n\n\n\n\n\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        # Check that prompts show default values
        expect { command.execute }.to output(
          /\[claude\].*\[--dangerously-skip-permissions\].*\[\/soba:plan {{issue-number}}\].*\[claude\].*\[--dangerously-skip-permissions\].*\[\/soba:implement {{issue-number}}\]/m
        ).to_stdout

        # Check that config applies default values when Enter is pressed
        config = YAML.safe_load_file(config_path)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
      end

      it "applies default values for phase commands when empty input is given" do
        # すべてのプロンプトで空入力（Enterキー）を入力
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\n\n\n\n\n\n\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        # phase設定が作成され、デフォルト値が適用されていることを確認
        expect(config['phase']).not_to be_nil
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
      end

      it "allows partial customization with some default values" do
        # plan commandはカスタマイズ、他はデフォルト値を使用
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\ncustom-claude\n\n\n\n\n\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['phase']['plan']['command']).to eq('custom-claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
      end

      context "with label creation" do
        let(:github_client) { instance_double(Soba::Infrastructure::GitHubClient) }
        let(:repository) { "douhashi/soba" }

        before do
          allow(Soba::Infrastructure::GitHubClient).to receive(:new).and_return(github_client)
        end

        it "creates labels after configuration file is created" do
          input = StringIO.new("#{repository}\n1\n20\n\n\n\n\nskip\nskip\ny\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Expect label creation calls
          expect(github_client).to receive(:list_labels).with(repository).and_return([])
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

          expect { command.execute }.to output(/Creating GitHub labels.*soba:planning.*created/m).to_stdout

          expect(config_path).to exist
        end

        it "skips label creation when user declines" do
          input = StringIO.new("#{repository}\n1\n20\n\n\n\n\nskip\nskip\nn\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Should not call any label methods
          expect(github_client).not_to receive(:list_labels)
          expect(github_client).not_to receive(:create_label)

          expect { command.execute }.to output(/Skipping label creation/).to_stdout
        end

        it "skips existing labels" do
          input = StringIO.new("#{repository}\n1\n20\n\n\n\n\nskip\nskip\ny\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          # Return existing labels
          existing_labels = [
            { name: "soba:planning", color: "1e90ff" },
            { name: "soba:doing", color: "ffd700" },
          ]
          expect(github_client).to receive(:list_labels).with(repository).and_return(existing_labels)

          # Only create missing labels
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

          expect { command.execute }.to output(/soba:planning.*already exists.*soba:ready.*created/m).to_stdout
        end

        it "handles label creation errors gracefully" do
          input = StringIO.new("#{repository}\n1\n20\n\n\n\n\nskip\nskip\ny\n")
          allow($stdin).to receive(:gets) { input.gets }
          allow($stdin).to receive(:noecho).and_yield(input)

          expect(github_client).to receive(:list_labels).with(repository).and_return([])
          expect(github_client).to receive(:create_label).
            with(repository, "soba:planning", "1e90ff", "Planning phase").
            and_raise(Soba::Infrastructure::GitHubClientError, "Insufficient permissions")

          expect { command.execute }.to output(/Failed to create label.*Insufficient permissions/m).to_stdout

          # Config should still be created
          expect(config_path).to exist
        end
      end

      it "uses correct default values for workflow phase commands" do
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nclaude\n--dangerously-skip-permissions\n\nclaude\n--dangerously-skip-permissions\n\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['phase']['plan']['command']).to eq('claude')
        expect(config['phase']['plan']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['plan']['parameter']).to eq('/soba:plan {{issue-number}}')
        expect(config['phase']['implement']['command']).to eq('claude')
        expect(config['phase']['implement']['options']).to eq(['--dangerously-skip-permissions'])
        expect(config['phase']['implement']['parameter']).to eq('/soba:implement {{issue-number}}')
      end

      it "skips workflow commands when skip is entered" do
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['phase']).to be_nil
      end

      it "validates repository format" do
        input = StringIO.new("invalid\ndouhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Invalid format/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
      end

      it "uses default values when empty input" do
        input = StringIO.new("douhashi/soba\n\n\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')
      end

      context "with git repository detection" do
        it "detects GitHub repository from git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = StringIO.new("\n1\n20\n\n\n\n\nskip\nskip\n")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[user\/repo\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('user/repo')
        end

        it "handles SSH format git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("git@github.com:owner/project.git\n")

          input = StringIO.new("\n1\n20\n\n\n\n\nskip\nskip\n")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[owner\/project\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('owner/project')
        end

        it "allows manual override of detected repository" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = StringIO.new("different/repo\n1\n20\n\n\n\n\nskip\nskip\n")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[user\/repo\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('different/repo')
        end
      end
    end

    context "when config file already exists" do
      before do
        config_path.dirname.mkpath
        File.write(config_path, "existing: config")
      end

      it "asks for confirmation before overwriting" do
        input = StringIO.new("y\ndouhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(
          /already exists.*Configuration created successfully/m
        ).to_stdout

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

    context "with .gitignore handling" do
      let(:gitignore_path) { Pathname.new(temp_dir).join('.gitignore') }

      before do
        File.write(gitignore_path, "*.log\n")
      end

      it "adds .soba to .gitignore when requested" do
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\ny\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Added .soba\/ to .gitignore/).to_stdout

        gitignore_content = File.read(gitignore_path)
        expect(gitignore_content).to include('.soba/')
      end

      it "does not add .soba when already present" do
        File.write(gitignore_path, "*.log\n.soba/\n")
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.not_to output(/Add .soba\/ to .gitignore/).to_stdout
      end
    end

    context "with environment variable detection" do
      it "detects when GITHUB_TOKEN is set" do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('test_token')
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is set/).to_stdout
      end

      it "warns when GITHUB_TOKEN is not set" do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
        input = StringIO.new("douhashi/soba\n1\n20\n\n\n\n\nskip\nskip\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is not set/).to_stdout
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
        allow(Dir).to receive(:exist?).with('.git').and_return(true)
        allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/douhashi/soba.git\n")

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
        expect(config['workflow']['phase_labels']['planning']).to eq('soba:planning')
        expect(config['workflow']['phase_labels']['ready']).to eq('soba:ready')
        expect(config['workflow']['phase_labels']['doing']).to eq('soba:doing')
        expect(config['workflow']['phase_labels']['review_requested']).to eq('soba:review-requested')

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