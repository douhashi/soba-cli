# soba CLI テスト戦略

## テストピラミッド

```
      /\
     /  \     E2E (5%)
    /────\    統合テスト (20%)
   /──────\
  /────────\  ユニットテスト (75%)
```

## テストレベル

### 1. ユニットテスト

個別クラス・メソッドの動作検証。実実装を使用して正確性を確保。

```ruby
RSpec.describe Issue do
  describe '#priority' do
    let(:issue) { described_class.new(labels: ['critical']) }

    it 'returns high for critical issues' do
      expect(issue.priority).to eq(:high)
    end
  end
end
```

### 2. 統合テスト

コンポーネント間連携とAPI連携の検証。VCRでHTTP記録。

```ruby
RSpec.describe GitHubClient, :vcr do
  it 'fetches issues from repository' do
    issues = client.fetch_issues('owner/repo')
    expect(issues).to be_an(Array)
  end
end
```

### 3. E2Eテスト

CLIコマンド全体の動作確認。

```ruby
RSpec.describe 'CLI', type: :e2e do
  it 'lists issues' do
    output = `bin/soba issue list owner/repo`
    expect($?).to be_success
    expect(output).to include('Issues')
  end
end
```

## テスト構成

```ruby
# spec/spec_helper.rb
require 'simplecov'
SimpleCov.start { minimum_coverage 90 }

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.order = :random
end
```

## モック戦略

**重要: モックの利用は外部のAPI連携のみに限定する。それ以外のテスト時は必ず実実装を利用する。**

```ruby
# 外部API連携のみモック化
module MockHelpers
  def stub_github_api_response
    stub_request(:get, /api.github.com/).
      to_return(status: 200, body: '[]', headers: {})
  end
end
```

## VCR設定

```ruby
VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr'
  config.hook_into :webmock
  config.filter_sensitive_data('<TOKEN>') { ENV['GITHUB_TOKEN'] }
end
```

## CI/CD

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec rspec
```

## カバレッジ目標

| レイヤー | 目標 |
|---------|------|
| Domain | 95%+ |
| Services | 90%+ |
| Infrastructure | 85%+ |
| CLI | 80%+ |

## ベストプラクティス

- AAAパターン（Arrange, Act, Assert）
- 1テスト1アサーション
- テストの独立性確保
- 明確なテスト名
- 実実装の利用（外部API以外はモック化禁止）