#!/usr/bin/env bash
#
# Build soba CLI as a standalone binary using Tebako
#
# Usage:
#   ./scripts/build-tebako.sh [options]
#
# Options:
#   --help          Show this help message
#   --check-docker  Check Docker availability
#   --validate      Validate build environment
#   --show-config   Show build configuration
#   --platform PLATFORM  Target platform (default: linux-x64)
#   --output DIR    Output directory (default: dist/)
#   --verbose       Enable verbose output

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUBY_VERSION="3.3.7"
TEBAKO_VERSION="0.9.4"
ENTRY_POINT="exe/soba"
OUTPUT_DIR="${PROJECT_ROOT}/dist"
PLATFORM="linux-x64"
VERBOSE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Show help
show_help() {
    head -n 14 "$0" | tail -n 12 | sed 's/^# //' | sed 's/^#//'
}

# Check Docker availability
check_docker() {
    log_info "Checking Docker availability..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available. Please install Docker first."
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or not accessible."
        return 1
    fi

    log_success "Docker is available"
    docker --version
    return 0
}

# Validate build environment
validate_environment() {
    log_info "Validating build environment..."

    # Check Docker
    if ! check_docker; then
        return 1
    fi

    # Check project structure
    if [[ ! -f "${PROJECT_ROOT}/Gemfile" ]]; then
        log_error "Gemfile not found in project root"
        return 1
    fi

    if [[ ! -f "${PROJECT_ROOT}/${ENTRY_POINT}" ]]; then
        log_error "Entry point ${ENTRY_POINT} not found"
        return 1
    fi

    log_success "Validation completed successfully"
    return 0
}

# Show build configuration
show_config() {
    log_info "Build configuration:"
    echo "  PROJECT_ROOT: ${PROJECT_ROOT}"
    echo "  RUBY_VERSION: ${RUBY_VERSION}"
    echo "  TEBAKO_VERSION: ${TEBAKO_VERSION}"
    echo "  ENTRY_POINT: ${ENTRY_POINT}"
    echo "  OUTPUT_DIR: ${OUTPUT_DIR}"
    echo "  PLATFORM: ${PLATFORM}"
}

# Prepare output directory
prepare_output_dir() {
    log_info "Preparing output directory..."

    if [[ ! -d "${OUTPUT_DIR}" ]]; then
        mkdir -p "${OUTPUT_DIR}"
        log_success "Created output directory: ${OUTPUT_DIR}"
    else
        log_info "Output directory already exists: ${OUTPUT_DIR}"
    fi
}

# Build with Tebako
build_binary() {
    log_info "Building soba binary with Tebako..."
    log_info "Target platform: ${PLATFORM}"

    # Prepare output directory
    prepare_output_dir

    # Set output filename based on platform
    case "${PLATFORM}" in
        linux-x64)
            OUTPUT_FILE="${OUTPUT_DIR}/soba-linux-x64"
            ;;
        darwin-x64)
            OUTPUT_FILE="${OUTPUT_DIR}/soba-darwin-x64"
            ;;
        darwin-arm64)
            OUTPUT_FILE="${OUTPUT_DIR}/soba-darwin-arm64"
            ;;
        *)
            log_error "Unsupported platform: ${PLATFORM}"
            return 1
            ;;
    esac

    log_info "Output file: ${OUTPUT_FILE}"

    # Docker command for Tebako build
    DOCKER_CMD=(
        docker run
        --rm
        -v "${PROJECT_ROOT}:/app"
        -v "${OUTPUT_DIR}:/output"
        -w /app
    )

    if [[ ${VERBOSE} -eq 1 ]]; then
        DOCKER_CMD+=(-e TEBAKO_VERBOSE=1)
    fi

    # Use official Tebako image
    DOCKER_CMD+=(
        "ghcr.io/tamatebako/tebako:${TEBAKO_VERSION}"
        tebako press
        --root=/app
        --entry-point="${ENTRY_POINT}"
        --output="/output/$(basename "${OUTPUT_FILE}")"
        --Ruby="${RUBY_VERSION}"
    )

    log_info "Executing Tebako build..."
    if [[ ${VERBOSE} -eq 1 ]]; then
        echo "Docker command: ${DOCKER_CMD[*]}"
    fi

    if "${DOCKER_CMD[@]}"; then
        log_success "Build completed successfully!"
        log_info "Binary created: ${OUTPUT_FILE}"

        # Make the binary executable
        chmod +x "${OUTPUT_FILE}"

        # Show binary info
        if [[ -f "${OUTPUT_FILE}" ]]; then
            log_info "Binary size: $(du -h "${OUTPUT_FILE}" | cut -f1)"
        fi
    else
        log_error "Build failed"
        return 1
    fi
}

# Test built binary
test_binary() {
    local binary_path="$1"

    log_info "Testing built binary..."

    if [[ ! -f "${binary_path}" ]]; then
        log_error "Binary not found: ${binary_path}"
        return 1
    fi

    # Test --version
    log_info "Testing: ${binary_path} --version"
    if "${binary_path}" --version; then
        log_success "Version check passed"
    else
        log_error "Version check failed"
        return 1
    fi

    # Test --help
    log_info "Testing: ${binary_path} --help"
    if "${binary_path}" --help > /dev/null 2>&1; then
        log_success "Help check passed"
    else
        log_error "Help check failed"
        return 1
    fi

    log_success "Binary tests completed successfully"
}

# Main function
main() {
    local action="build"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --check-docker)
                action="check_docker"
                shift
                ;;
            --validate)
                action="validate"
                shift
                ;;
            --show-config)
                action="show_config"
                shift
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --test)
                action="test"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Execute action
    case ${action} in
        check_docker)
            check_docker
            ;;
        validate)
            validate_environment
            ;;
        show_config)
            show_config
            ;;
        test)
            # Test the most recent build
            case "${PLATFORM}" in
                linux-x64)
                    test_binary "${OUTPUT_DIR}/soba-linux-x64"
                    ;;
                *)
                    test_binary "${OUTPUT_DIR}/soba-${PLATFORM}"
                    ;;
            esac
            ;;
        build)
            if validate_environment; then
                show_config
                build_binary
            else
                exit 1
            fi
            ;;
    esac
}

# Run main function
main "$@"