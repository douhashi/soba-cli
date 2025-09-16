# frozen_string_literal: true

require "spec_helper"
require "soba/commands/init"
require "tmpdir"
require "stringio"

RSpec.describe Soba::Commands::Init do
  let(:command) { described_class.new }

  describe "#execute" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:config_path) { Pathname.new(temp_dir).join('.osoba', 'config.yml') }

    before do
      allow(Pathname).to receive(:pwd).and_return(Pathname.new(temp_dir))
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context "when config file does not exist" do
      it "creates a new configuration file" do
        input = StringIO.new("douhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(input)

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
      end

      it "accepts direct token input" do
        input = StringIO.new("douhashi/soba\n2\nsecret_token\n30\n")
        allow($stdin).to receive(:gets) { input.gets }
        allow($stdin).to receive(:noecho).and_yield(StringIO.new("secret_token\n"))

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('secret_token')
      end

      it "validates repository format" do
        input = StringIO.new("invalid\ndouhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Invalid format/).to_stdout

        expect(config_path).to exist
        config = YAML.safe_load_file(config_path)
        expect(config['github']['repository']).to eq('douhashi/soba')
      end

      it "uses default values when empty input" do
        input = StringIO.new("douhashi/soba\n\n\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

        config = YAML.safe_load_file(config_path)
        expect(config['github']['token']).to eq('${GITHUB_TOKEN}')
        expect(config['workflow']['interval']).to eq(20)
      end

      context "with git repository detection" do
        it "detects GitHub repository from git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = StringIO.new("\n1\n20\n")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[user\/repo\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('user/repo')
        end

        it "handles SSH format git remote" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("git@github.com:owner/project.git\n")

          input = StringIO.new("\n1\n20\n")
          allow($stdin).to receive(:gets) { input.gets }

          expect { command.execute }.to output(/\[owner\/project\]/).to_stdout

          config = YAML.safe_load_file(config_path)
          expect(config['github']['repository']).to eq('owner/project')
        end

        it "allows manual override of detected repository" do
          allow(Dir).to receive(:exist?).with('.git').and_return(true)
          allow(command).to receive(:`).with('git config --get remote.origin.url 2>/dev/null').and_return("https://github.com/user/repo.git\n")

          input = StringIO.new("different/repo\n1\n20\n")
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
        input = StringIO.new("y\ndouhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/already exists/).to_stdout
        expect { command.execute }.to output(/Configuration created successfully/).to_stdout

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

      it "adds .osoba to .gitignore when requested" do
        input = StringIO.new("douhashi/soba\n1\n20\ny\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/Added .osoba\/ to .gitignore/).to_stdout

        gitignore_content = File.read(gitignore_path)
        expect(gitignore_content).to include('.osoba/')
      end

      it "does not add .osoba when already present" do
        File.write(gitignore_path, "*.log\n.osoba/\n")
        input = StringIO.new("douhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.not_to output(/Add .osoba\/ to .gitignore/).to_stdout
      end
    end

    context "with environment variable detection" do
      it "detects when GITHUB_TOKEN is set" do
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('test_token')
        input = StringIO.new("douhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is set/).to_stdout
      end

      it "warns when GITHUB_TOKEN is not set" do
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
        input = StringIO.new("douhashi/soba\n1\n20\n")
        allow($stdin).to receive(:gets) { input.gets }

        expect { command.execute }.to output(/GITHUB_TOKEN environment variable is not set/).to_stdout
      end
    end

    context "error handling" do
      it "handles interrupt gracefully" do
        allow($stdin).to receive(:gets).and_raise(Interrupt)

        expect { command.execute }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end
end