# soba CLI コーディング規約

## 基本原則

1. **可読性優先** - シンプルで理解しやすいコード
2. **Ruby Way** - Rubyの慣習に従う
3. **一貫性** - プロジェクト全体で統一

## 命名規則

| 種類 | 規則 | 例 |
|-----|------|-----|
| ファイル | snake_case | `issue_monitor.rb` |
| クラス | PascalCase | `IssueMonitor` |
| メソッド | snake_case | `fetch_issues` |
| 定数 | SCREAMING_SNAKE | `MAX_RETRIES` |
| 述語メソッド | 疑問符付き | `valid?` |

## ファイル構造

```ruby
# frozen_string_literal: true

require 'standard_library'
require_relative '../domain/issue'

module Soba
  class IssueMonitor
    # クラス実装
  end
end
```

### GLIコマンド構造

```ruby
# bin/soba
#!/usr/bin/env ruby
require 'gli'

include GLI::App

desc 'Global option'
flag [:c, :config]

command :issue do |c|
  c.action do |global, options, args|
    # コマンド実装
  end
end

exit run(ARGV)
```

## クラス設計

```ruby
class IssueMonitor
  attr_reader :client

  def initialize(client)
    @client = client
  end

  def start
    validate!
    monitor_loop
  end

  private

  def validate!
    raise ConfigError unless valid?
  end
end
```

## メソッド設計

- 10行以内を目安
- 引数は3個まで（オプションハッシュ推奨）
- ガード節で早期リターン

```ruby
def process(issue)
  return unless issue.valid?
  return if issue.closed?

  perform_processing(issue)
end
```

## エラーハンドリング

```ruby
module Soba
  class Error < StandardError; end
  class ConfigError < Error; end
end

def fetch_issue(id)
  client.issue(id)
rescue Octokit::NotFound
  nil
end
```

## Rubocop設定（主要項目）

```yaml
AllCops:
  TargetRubyVersion: 3.2

Layout/LineLength:
  Max: 100

Metrics/MethodLength:
  Max: 15

Style/StringLiterals:
  EnforcedStyle: double_quotes
```

## テストコード

```ruby
RSpec.describe IssueMonitor do
  let(:monitor) { described_class.new(client) }

  describe '#start' do
    context 'when valid' do
      it 'starts monitoring' do
        expect(monitor).to receive(:monitor_loop)
        monitor.start
      end
    end
  end
end
```

## コードレビューチェックリスト

- [ ] 命名規則に従っているか
- [ ] 単一責任の原則を守っているか
- [ ] テストが書かれているか
- [ ] エラーハンドリングが適切か
