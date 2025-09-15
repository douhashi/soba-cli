# soba CLI 実装ガイド

## 実装フェーズ

### Phase 1: 基盤構築（1週目）

```bash
# Gemfile作成
bundle init
bundle add gli dry-container dry-auto_inject faraday octokit
bundle add --group development,test rspec webmock rubocop
```

基本ファイル:
- `bin/soba` - 実行ファイル
- `lib/soba.rb` - エントリポイント
- `lib/soba/container/container.rb` - DI設定

### Phase 2: CLIコマンド（2週目）

```ruby
# bin/soba
#!/usr/bin/env ruby
require 'gli'
require 'soba'

include GLI::App

program_desc 'GitHub Issue to Claude Code workflow automation'
version Soba::VERSION

desc 'Manage issues'
command :issue do |c|
  c.desc 'List issues'
  c.command :list do |list|
    list.action do |global_options, options, args|
      Soba::Commands::Issue::List.new.execute(args[0])
    end
  end
end

exit run(ARGV)
```

実装順序:
1. `config` - 設定確認
2. `issue list` - 一覧取得
3. `issue watch` - 監視機能

### Phase 3: ドメインモデル（3週目）

```ruby
# lib/soba/domain/entities/issue.rb
module Soba
  class Issue
    attr_reader :id, :title, :state

    def open?
      state == 'open'
    end
  end
end
```

### Phase 4: 外部連携（4週目）

```ruby
# lib/soba/infrastructure/github/client.rb
module Soba
  class GitHubClient
    def initialize(token:)
      @octokit = Octokit::Client.new(access_token: token)
    end

    def issues(repo)
      @octokit.issues(repo)
    end
  end
end
```

## Gem構成

```ruby
# soba.gemspec
Gem::Specification.new do |spec|
  spec.name = "soba"
  spec.version = "0.1.0"
  spec.files = Dir["lib/**/*", "bin/*"]
  spec.executables = ["soba"]
  spec.add_dependency "gli", "~> 2.21"
end
```

## Docker化

```dockerfile
FROM ruby:3.2-slim
WORKDIR /app
COPY . .
RUN bundle install
ENTRYPOINT ["bin/soba"]
```