#!/bin/bash

# 色の定義
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# セクション開始の装飾関数
print_section() {
    echo
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
    echo
}

# サブセクションの装飾関数
print_subsection() {
    echo -e "${BOLD}${YELLOW}► $1${NC}"
}

# 成功メッセージ
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# エラーメッセージ
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 警告メッセージ
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 情報メッセージ
print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# 処理中メッセージ
print_processing() {
    echo -e "${PURPLE}  → $1${NC}"
}

# 完了メッセージ（大）
print_completion() {
    echo
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  $1${NC}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════════════${NC}"
    echo
}