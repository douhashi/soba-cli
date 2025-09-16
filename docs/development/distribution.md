# soba CLI 配布戦略

## 概要

soba CLIは、Tebakoを使用してスタンドアロンバイナリとして配布されます。これにより、エンドユーザーはRuby環境のインストールや設定を行うことなく、単一の実行可能ファイルをダウンロードして即座に使用できます。

## Tebakoとは

Tebakoは、Rubyアプリケーションを自己完結型の実行可能バイナリにパッケージングするツールです。DwarFS（読み取り専用ファイルシステム）を使用して、アプリケーションコード、依存関係、Rubyランタイムを単一のバイナリに統合します。

### 主な特徴
- Ruby 3.4.1まで対応（2024年12月現在）
- Linux（glibc/musl）、macOS、Windows対応
- Dockerベースの簡単なビルドプロセス
- ネイティブエクステンションを含むgemもサポート

## ビルドプロセス

### 1. 開発環境でのビルド

#### Dockerを使用したビルド（推奨）

```bash
# Linux (Ubuntu) 向けビルド
docker run -v $PWD:/mnt/w \
  -t ghcr.io/tamatebako/tebako-ubuntu-20.04:latest \
  tebako press \
    --root=/mnt/w \
    --entry-point=bin/soba \
    --output=/mnt/w/dist/soba-linux-x64 \
    --ruby=3.3.7

# macOS向けビルド
docker run -v $PWD:/mnt/w \
  -t ghcr.io/tamatebako/tebako-macos-ventura:latest \
  tebako press \
    --root=/mnt/w \
    --entry-point=bin/soba \
    --output=/mnt/w/dist/soba-darwin-x64 \
    --ruby=3.3.7

# Windows向けビルド
docker run -v $PWD:/mnt/w \
  -t ghcr.io/tamatebako/tebako-windows-2022:latest \
  tebako press \
    --root=/mnt/w \
    --entry-point=bin/soba \
    --output=/mnt/w/dist/soba-windows-x64.exe \
    --ruby=3.3.7
```

#### ローカル環境でのビルド

```bash
# Tebakoのインストール
gem install tebako

# セットアップ
tebako setup

# パッケージング
tebako press \
  --root=. \
  --entry-point=bin/soba \
  --output=dist/soba \
  --ruby=3.3.7
```

### 2. ビルドオプション

- `--strip`: 開発モードを有効化（キャッシュと整合性チェックを緩和）
- `--patchelf`: Linuxディストリビューション間の前方互換性を確保
- `--log-level`: ログレベルの設定（error, warn, info, debug, trace）

## CI/CDパイプライン

### GitHub Actions設定例

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            platform: linux-x64
            container: ubuntu-20.04
          - os: macos-latest
            platform: darwin-x64
            container: macos-ventura
          - os: macos-latest
            platform: darwin-arm64
            container: macos-ventura-arm64
          - os: windows-latest
            platform: windows-x64
            container: windows-2022

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Build with Tebako
        run: |
          docker run -v $PWD:/mnt/w \
            -t ghcr.io/tamatebako/tebako-${{ matrix.container }}:latest \
            tebako press \
              --root=/mnt/w \
              --entry-point=bin/soba \
              --output=/mnt/w/dist/soba-${{ matrix.platform }} \
              --ruby=3.3.7

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: soba-${{ matrix.platform }}
          path: dist/soba-${{ matrix.platform }}*

  release:
    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: soba-*/*
          generate_release_notes: true
```

## 配布チャネル

### 1. GitHub Releases

直接ダウンロード用のURLを提供：

```bash
# Linux
curl -L https://github.com/yourusername/soba/releases/latest/download/soba-linux-x64 \
  -o /usr/local/bin/soba
chmod +x /usr/local/bin/soba

# macOS
curl -L https://github.com/yourusername/soba/releases/latest/download/soba-darwin-x64 \
  -o /usr/local/bin/soba
chmod +x /usr/local/bin/soba

# Windows (PowerShell)
Invoke-WebRequest -Uri https://github.com/yourusername/soba/releases/latest/download/soba-windows-x64.exe `
  -OutFile "$env:LOCALAPPDATA\soba\soba.exe"
```

### 2. インストールスクリプト

ワンライナーインストール用のスクリプト：

```bash
#!/bin/bash
# install.sh

set -e

REPO="yourusername/soba"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# OSとアーキテクチャの検出
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux*)   PLATFORM="linux" ;;
  Darwin*)  PLATFORM="darwin" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  *)        echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64)  ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

BINARY_NAME="soba-${PLATFORM}-${ARCH}"
if [ "$PLATFORM" = "windows" ]; then
  BINARY_NAME="${BINARY_NAME}.exe"
fi

# 最新版のダウンロード
echo "Downloading soba for ${PLATFORM}-${ARCH}..."
curl -L "https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}" \
  -o "${INSTALL_DIR}/soba"

chmod +x "${INSTALL_DIR}/soba"

echo "soba has been installed to ${INSTALL_DIR}/soba"
```

使用方法：
```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/soba/main/install.sh | bash
```

### 3. Homebrew Formula（将来的な拡張）

```ruby
class Soba < Formula
  desc "GitHub Issue driven workflow automation CLI"
  homepage "https://github.com/yourusername/soba"
  version "1.0.0"

  if OS.mac? && Hardware::CPU.arm?
    url "https://github.com/yourusername/soba/releases/download/v1.0.0/soba-darwin-arm64"
    sha256 "..."
  elsif OS.mac?
    url "https://github.com/yourusername/soba/releases/download/v1.0.0/soba-darwin-x64"
    sha256 "..."
  elsif OS.linux?
    url "https://github.com/yourusername/soba/releases/download/v1.0.0/soba-linux-x64"
    sha256 "..."
  end

  def install
    bin.install "soba"
  end
end
```

## パフォーマンス考慮事項

### ビルド時間
- 初回ビルド: 最大1時間（環境セットアップ含む）
- 2回目以降: 数分程度

### バイナリサイズ
- 典型的なサイズ: 30-50MB
- 最適化オプション使用時: 20-40MB

### 起動時間
- 初回起動: DwarFSの展開により若干の遅延
- 2回目以降: OSのキャッシュにより高速化

## トラブルシューティング

### よくある問題と解決策

1. **libc互換性エラー（Linux）**
   - `--patchelf`オプションを使用してビルド

2. **ネイティブエクステンションのエラー**
   - Tebakoがサポートするgemバージョンを確認
   - 必要に応じてgemのバージョンを調整

3. **Windows Defenderによる誤検知**
   - コード署名証明書の取得を検討
   - ユーザーガイドに除外設定の手順を記載

## セキュリティ考慮事項

1. **コード署名**
   - macOS: Developer ID証明書で署名
   - Windows: Authenticode証明書で署名

2. **チェックサム**
   - 各リリースにSHA256ハッシュを提供

3. **自動更新機能**
   - セルフアップデート機能の実装を検討

## 今後の計画

- [ ] ARM Linux対応
- [ ] Alpine Linux（musl libc）対応
- [ ] 自動更新機能の実装
- [ ] パッケージマネージャへの登録（Homebrew、Scoop等）