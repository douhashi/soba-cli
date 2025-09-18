# リリースプロセス

## 概要

soba CLIのリリースプロセスは、Tebakoを使用してスタンドアロンバイナリを作成し、GitHub Releasesで配布する仕組みです。

## ビルドシステム

### Tebako

Tebakoは、Rubyアプリケーションをスタンドアロンバイナリとしてパッケージングするツールです。

- **バージョン**: 0.9.4
- **Ruby**: 3.3.7
- **ビルドツール**: Docker（クロスプラットフォームビルド用）

### サポートプラットフォーム

現在サポート:
- Linux x64

将来サポート予定:
- macOS x64
- macOS ARM64 (Apple Silicon)
- Windows x64

## ローカルビルド

### 前提条件

- Docker がインストールされていること
- Docker デーモンが起動していること

### ビルド手順

1. **環境検証**
   ```bash
   ./scripts/build-tebako.sh --validate
   ```

2. **設定確認**
   ```bash
   ./scripts/build-tebako.sh --show-config
   ```

3. **バイナリビルド**
   ```bash
   # デフォルト（Linux x64）
   ./scripts/build-tebako.sh

   # プラットフォーム指定
   ./scripts/build-tebako.sh --platform linux-x64

   # 詳細出力付き
   ./scripts/build-tebako.sh --verbose
   ```

4. **ビルド成果物のテスト**
   ```bash
   ./scripts/build-tebako.sh --test
   ```

5. **Rakeタスク経由でのビルド**
   ```bash
   # ビルド
   rake build:tebako

   # テスト
   rake build:test_binary

   # クリーン
   rake build:clean
   ```

### ビルド成果物

- 出力ディレクトリ: `dist/`
- バイナリ名: `soba-<platform>`
  - 例: `soba-linux-x64`

## CI/CDリリースプロセス

### 自動リリースの流れ

1. **タグプッシュによるトリガー**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **GitHub Actionsワークフロー**
   - `.github/workflows/release.yml` が実行される
   - 各プラットフォーム向けにビルドジョブが並列実行
   - テスト実行
   - バイナリ生成

3. **GitHub Release作成**
   - 全プラットフォームのビルド完了後
   - リリースノートの自動生成
   - バイナリアセットのアップロード

### 手動リリース

GitHub Actionsの「Run workflow」から手動でリリースワークフローを実行することも可能です。

## リリースタグ規約

セマンティックバージョニング（SemVer）を採用:

- **形式**: `v<major>.<minor>.<patch>`
- **例**: `v1.0.0`, `v1.2.3`, `v2.0.0-beta.1`

### バージョン番号の意味

- **Major**: 後方互換性のない変更
- **Minor**: 後方互換性のある機能追加
- **Patch**: バグ修正

## トラブルシューティング

### ビルドエラー

#### Docker が見つからない
```
[ERROR] Docker is not available. Please install Docker first.
```
**解決策**: Dockerをインストールしてください

#### Docker デーモンが起動していない
```
[ERROR] Docker daemon is not running or not accessible.
```
**解決策**: Docker デーモンを起動してください
```bash
# Linux
sudo systemctl start docker

# macOS
open -a Docker
```

#### ビルド失敗
```
[ERROR] Build failed
```
**解決策**:
1. Docker イメージのプル状態を確認
2. ディスク容量を確認
3. `--verbose` オプションで詳細ログを確認

### バイナリ実行エラー

#### Permission denied
```bash
chmod +x soba-linux-x64
```

#### ライブラリ依存関係エラー
Tebakoビルドには必要なライブラリが含まれているはずですが、問題が発生した場合:
```bash
ldd soba-linux-x64  # Linux
```

## セキュリティ考慮事項

### 将来の実装予定

1. **コード署名**
   - macOS: Developer ID による署名
   - Windows: Authenticode 署名

2. **チェックサム提供**
   - SHA256 ハッシュの公開
   - 署名付きチェックサムファイル

3. **脆弱性スキャン**
   - ビルド時の依存関係スキャン
   - バイナリのウイルススキャン

## 参考リンク

- [Tebako公式ドキュメント](https://github.com/tamatebako/tebako)
- [GitHub Releases API](https://docs.github.com/en/rest/releases/releases)
- [Semantic Versioning](https://semver.org/)