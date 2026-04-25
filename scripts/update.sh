#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly UPDATE_INFO_URL="https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl"
readonly RELEASE_BASE="https://github.com/JetBrains/junie/releases/download"
readonly CHANNEL="release"

readonly PLATFORMS=("linux-amd64" "linux-aarch64" "macos-amd64" "macos-aarch64")

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_current_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1
}

get_latest_version() {
    curl -fsSL "$UPDATE_INFO_URL" \
        | grep '"platform":"linux-amd64"' \
        | tail -1 \
        | grep -o '"version":"[^"]*"' \
        | sed 's/"version":"\([^"]*\)"/\1/'
}

fetch_hash() {
    local version="$1"
    local platform="$2"
    local url="${RELEASE_BASE}/${version}/junie-${CHANNEL}-${version}-${platform}.zip"
    nix-prefetch-url "$url" 2>/dev/null | tail -1 | tr -d '\n'
}

update_package_version() {
    local version="$1"
    sed -i.bak "s/version = \".*\"/version = \"$version\"/" package.nix
}

update_platform_hash() {
    local platform="$1"
    local hash="$2"
    local temp_file
    temp_file=$(mktemp)

    awk -v platform="$platform" -v hash="$hash" '
        /hashes = \{/ { in_block=1 }
        in_block && $0 ~ "\"" platform "\"" {
            sub(/= "[^"]*"/, "= \"" hash "\"")
        }
        in_block && /\};/ { in_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

cleanup_backup_files() {
    rm -f package.nix.bak
}

update_to_version() {
    local new_version="$1"

    log_info "Updating to version $new_version..."

    update_package_version "$new_version"

    log_info "Fetching binary hashes for all platforms..."
    for platform in "${PLATFORMS[@]}"; do
        log_info "  Fetching hash for $platform..."
        local hash
        hash=$(fetch_hash "$new_version" "$platform")
        if [ -z "$hash" ]; then
            log_error "Failed to fetch hash for $platform"
            mv package.nix.bak package.nix
            exit 1
        fi
        log_info "  $platform: $hash"
        update_platform_hash "$platform" "$hash"
    done

    cleanup_backup_files

    log_info "Verifying build..."
    if ! nix build .#junie > /dev/null 2>&1; then
        log_error "Build verification failed"
        return 1
    fi

    log_info "✅ Build successful!"
    return 0
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "package.nix" ]; then
        log_error "flake.nix or package.nix not found. Please run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
    command -v nix-prefetch-url >/dev/null 2>&1 || { log_error "nix-prefetch-url is required but not installed."; exit 1; }
    command -v curl >/dev/null 2>&1 || { log_error "curl is required but not installed."; exit 1; }
}

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --version VERSION  Update to specific version
  --check            Only check for updates, don't apply
  --help             Show this help message

Examples:
  $0                       # Update to latest version
  $0 --check               # Check if update is available
  $0 --version 1417.47     # Update to specific version
EOF
}

parse_arguments() {
    local target_version=""
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --check)
                check_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    echo "$target_version|$check_only"
}

update_flake_lock() {
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating flake.lock..."
        nix flake update
    fi
}

show_changes() {
    echo ""
    log_info "Changes made:"
    git diff --stat package.nix flake.lock 2>/dev/null || true
}

main() {
    ensure_in_repository_root
    ensure_required_tools_installed

    local args
    args=$(parse_arguments "$@")
    local target_version
    target_version=$(echo "$args" | cut -d'|' -f1)
    local check_only
    check_only=$(echo "$args" | cut -d'|' -f2)

    local current_version
    current_version=$(get_current_version)
    local latest_version
    latest_version=$(get_latest_version)

    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    fi

    if [ -z "$latest_version" ]; then
        log_error "Failed to determine latest version"
        exit 1
    fi

    log_info "Current version: $current_version"
    log_info "Latest version:  $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi

    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version → $latest_version"
        exit 1
    fi

    update_to_version "$latest_version"

    log_info "Successfully updated junie from $current_version to $latest_version"

    update_flake_lock
    show_changes
}

main "$@"
