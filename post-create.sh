#!/bin/bash
set -e

# ベースディレクトリを取得（絶対パスに変換）
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# メッセージ出力関数を読み込む
source "${BASE_DIR}/setup/scripts/functions/print_message.sh"

# ログファイルの設定
LOG_DIR="/tmp/devcontainer-setup"
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOG_DIR}"

# ログ出力を設定（標準出力と標準エラー出力をログファイルにも記録）
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

print_section "Devcontainer Setup Started"
print_subsection "Log file: ${LOG_FILE}"

# Execute setup scripts for each phase
SETUP_DIR="${BASE_DIR}/setup"

# Detect and execute setup/[2-digit number]*.sh files in numerical order
# Debug output
print_subsection "Setup directory: ${SETUP_DIR}"

# Use bash glob pattern matching
script_count=0
for script_file in "${SETUP_DIR}"/[0-9][0-9]*.sh; do
    # Check if file actually exists
    if [[ -f "${script_file}" ]]; then
        script_count=$((script_count + 1))
        script_name=$(basename "${script_file}")
        print_subsection "Running ${script_name}..."
        chmod +x "${script_file}"
        if "${script_file}"; then
            print_success "${script_name} completed successfully"
        else
            print_error "Error occurred while running ${script_name}"
            exit 1
        fi
    fi
done

if [[ ${script_count} -eq 0 ]]; then
    print_error "No setup scripts found"
    print_subsection "Directory contents:"
    ls -la "${SETUP_DIR}"
fi

# Completion message
print_completion "All setup completed successfully!"
print_subsection "Log file saved at: ${LOG_FILE}"

# Add summary at the end of log
echo "" >> "${LOG_FILE}"
echo "=== Setup Summary ===" >> "${LOG_FILE}"
echo "Start time: $(date -r "${LOG_FILE}" +"%Y-%m-%d %H:%M:%S")" >> "${LOG_FILE}"
echo "End time: $(date +"%Y-%m-%d %H:%M:%S")" >> "${LOG_FILE}"
echo "Log file: ${LOG_FILE}" >> "${LOG_FILE}"
