#!/bin/bash
set -e

# ベースディレクトリを取得
BASE_DIR="$(dirname "$0")/.."

# MCP設定を読み込む
source "${BASE_DIR}/functions/mcp_config.sh"

MCP_NAME="markdownify-mcp"
REPO_URL="https://github.com/zcaceres/markdownify-mcp.git"
MCP_DIR="${MARKDOWNIFY_MCP_DIR}"

echo "Installing ${MCP_NAME}..." >&2

# ディレクトリの準備
# 安全性チェック: MCP_DIRが正しいパスであることを確認
if [[ -z "${MCP_DIR}" ]]; then
    echo "Error: MCP_DIR is not set" >&2
    exit 1
fi

if [[ ! "${MCP_DIR}" =~ ^${MCP_BASE_DIR}/ ]]; then
    echo "Error: Invalid MCP_DIR path: ${MCP_DIR}" >&2
    exit 1
fi

# 既存のディレクトリを削除
if [[ -d "${MCP_DIR}" ]]; then
    rm -rf "${MCP_DIR}"
fi

mkdir -p "$(dirname "${MCP_DIR}")"

# リポジトリのクローンとビルド
git clone "${REPO_URL}" "${MCP_DIR}" >&2
cd "${MCP_DIR}"
pnpm install >&2
pnpm run build >&2