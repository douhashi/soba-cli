#!/bin/bash

# MCPサーバの共通設定
# MCPサーバのベースディレクトリ
export MCP_BASE_DIR="${MCP_BASE_DIR:-/home/vscode/Documents/Cline/MCP}"

# markdownify-mcpのディレクトリ
export MARKDOWNIFY_MCP_DIR="${MCP_BASE_DIR}/markdownify-mcp"

# markdownify-mcpの実行ファイルパス
export MARKDOWNIFY_MCP_EXEC="${MARKDOWNIFY_MCP_DIR}/dist/index.js"

# uvのパス
export UV_PATH="${UV_PATH:-/home/vscode/.local/bin/uv}"