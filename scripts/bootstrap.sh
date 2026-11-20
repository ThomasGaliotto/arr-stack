#!/bin/bash
# =============================================================================
# BOOTSTRAP SCRIPT - Initial Setup and Volume Creation Checks
# Usage: ./scripts/bootstrap.sh [OPTIONS]
# Options: --dry-run, --force-recreate
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
HOST_DATA_ROOT="/srv/media"
HOST_CONFIG_ROOT="/srv/media-stack/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse command line arguments
DRY_RUN=false
FORCE_RECREATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --force-recreate) FORCE_RECREATE=true ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Function to check and create host directories
check_and_create_directories() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        log_info "Creating directory: $dir"
        
        # Check for sudo availability before creating system paths
        if [[ "$dir" == /srv/* ]]; then
            if command -v sudo &> /dev/null; then
                sudo mkdir -p "$dir" 2>/dev/null || {
                    log_error "Cannot create $dir. Please run manually: sudo mkdir -p '$dir'"
                    exit 1
                }
            else
                log_warn "sudo not available, skipping directory creation for system paths"
                return 0
            fi
        else
            # User-owned directories can be created without sudo
            mkdir -p "$dir" || {
                log_error "Cannot create $dir: $?"
                exit 1
            }
        fi
        
        # Set ownership to match host UID/GID (from environment or defaults)
        local uid="${HOST_UID:-$(id -u)}"
        local gid="${HOST_GID:-$(id -g)}"
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would set ownership: chown ${uid}:${gid} $dir"
        else
            sudo chown "${uid}:${gid}" "$dir" 2>/dev/null || {
                # Fallback without sudo if available
                chown "${uid}:${gid}" "$dir" 2>/dev/null || true
            }
        fi
        
    elif [ -d "$dir/.gitkeep" ]; then
        log_info "Directory exists with placeholder: $dir"
    else
        log_warn "Directory exists but without .gitkeep marker. Checking permissions..."
        
        local uid="${HOST_UID:-$(id -u)}"
        if [[ $(stat -c %U "$dir") != "$(whoami)" ]]; then
            log_info "Directory owned by different user: $(stat -c %U:%G $dir)"
        fi
    fi
    
    return 0
}

# Function to create data directory structure
create_data_structure() {
    local base_dir="$1"
    
    # Torrents subdirectories
    mkdir -p "$base_dir/torrents/incomplete" \
             "$base_dir/torrents/movies" \
             "$base_dir/torrents/tv" \
             "$base_dir/torrents/music" 2>/dev/null || true
    
    # Media library subdirectories  
    mkdir -p "$base_dir/media/movies" \
             "$base_dir/media/tv" \
             "$base_dir/media/music" 2>/dev/null || true
    
    log_info "Data structure created/verified at: $base_dir"
}

# Function to create config directory structure
create_config_structure() {
    local base_dir="$1"
    
    # Create all service configuration directories with .gitkeep placeholders
    for dir in gluetun qbittorrent sonarr radarr lidarr prowlarr bazarr jellyfin jellyseerr recyclarr; do
        mkdir -p "$base_dir/$dir" 2>/dev/null || true
        
        if [ ! -f "$base_dir/$dir/.gitkeep" ]; then
            echo "# Configuration for $dir service (managed by compose.yaml)" > "$base_dir/$dir/.gitkeep"
        fi
    done
    
    log_info "Config structure created/verified at: $base_dir"
}

# Function to create backups directory if needed
create_backup_directory() {
    local backup_dir="$PROJECT_ROOT/backups"  # Will be created by orchestrator or user
    
    mkdir -p "$backup_dir" 2>/dev/null || true
    
    log_info "Backup directory ready at: $backup_dir"
}

# Main bootstrap logic
main() {
    echo "=========================================="
    echo "ARR Media Stack Bootstrap Script"
    echo "=========================================="
    
    # Check Docker availability (non-blocking)
    if command -v docker &> /dev/null; then
        log_info "Docker is available: $(docker --version)"
    else
        log_warn "Docker not found in PATH. Skipping container checks."
    fi
    
    echo ""
    
    # Create host data structure (if paths are system-level)
    if [ -d "$HOST_DATA_ROOT" ]; then
        check_and_create_directories "$HOST_DATA_ROOT/torrents/incomplete"
        check_and_create_directories "$HOST_DATA_ROOT/media/movies"
        
        create_data_structure "$HOST_DATA_ROOT" || true
        
    else
        log_warn "Host data root not found: $HOST_DATA_ROOT"
        log_info "Skipping host directory creation (optional)"
    fi
    
    # Create config structure in project
    if [ -d "$PROJECT_ROOT/config" ]; then
        create_config_structure "$PROJECT_ROOT/config" || true
        
        # Verify all expected directories exist
        for dir in gluetun qbittorrent sonarr radarr lidarr prowlarr bazarr jellyfin jellyseerr recyclarr; do
            if [ ! -d "$PROJECT_ROOT/config/$dir" ]; then
                log_error "Missing config directory: $PROJECT_ROOT/config/$dir"
                exit 1
            fi
        done
        
    else
        log_warn "Config root not found at project level. Skipping."
    fi
    
    echo ""
    
    # Create backups directory (optional)
    create_backup_directory || true
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Bootstrap completed without making changes"
    else
        log_info "Bootstrap complete!"
        
        # Verify compose.yaml exists before suggesting deployment
        if [ -f "${PROJECT_ROOT}/compose.yaml" ]; then
            log_info "Docker Compose configuration found. Ready for deployment."
            
            # Check environment variables file
            if [ ! -f ".env.example" ]; then
                log_warn "Environment template not found: .env.example"
            else
                log_info "Environment template verified: .env.example"
            fi
            
        else
            log_error "compose.yaml not found. Cannot proceed with deployment."
            exit 1
        fi
        
    fi
    
}

# Run main function
main "$@"
