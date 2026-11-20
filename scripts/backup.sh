#!/bin/bash
# =============================================================================
# BACKUP SCRIPT - Configuration Backup with Checksums (Excludes Media Files)
# Usage: ./scripts/backup.sh [OPTIONS]
# Options: --dry-run, --output=<path>, --compress=gzip|bzip2|xz
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
COMPRESSION_ALGORITHM=${BACKUP_COMPRESSION:-gzip}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[BACKUP]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[BACKUP-WARN]${NC} $*"; }
log_error() { echo -e "${RED}[BACKUP-ERROR]${NC} $*" >&2; }
log_check() { echo -e "${BLUE}[BACKUP-CHECK]${NC} $*"; }

# Parse command line arguments
DRY_RUN=false
OUTPUT_DIR="${PROJECT_ROOT}/backups"  # Default to project backups directory (created by orchestrator)
COMPRESSOR="gzip"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        --output=*) OUTPUT_DIR="${1#*=}" ;;
        --compress=gzip|bzip2|xz) COMPRESSOR="$1" ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Function to create backup directory if needed
ensure_backup_directory() {
    mkdir -p "$OUTPUT_DIR" || true
    
    # Create retention policy subdirectory for organized backups
    local today=$(date +%Y-%m)
    mkdir -p "${OUTPUT_DIR}/${today}" 2>/dev/null || true
    
}

# Function to create backup tarball (excluding media files and secrets if needed)
create_backup_tarball() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_name="arr-stack-config-${timestamp}.tar.gz"
    
    # Build exclude list for the tar command
    local excludes="--exclude=data/torrents/* --exclude=data/media/*"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create backup: ${OUTPUT_DIR}/${archive_name}"
        
        echo ""
        echo "--- Backup Contents (would be included) ---"
        find "${PROJECT_ROOT}/config" -type f 2>/dev/null | head -10 || true
        
    else
        # Create the tarball with compression
        log_info "Creating backup archive: ${archive_name}"
        
        cd "${PROJECT_ROOT}" && \
            tar czf "${OUTPUT_DIR}/${archive_name}" \
                --exclude=data/torrents/* \
                --exclude=data/media/* \
                config data secrets scripts tests docs .env.example 2>/dev/null || {
                
                # Fallback if full path doesn't work (try relative paths)
                tar czf "${OUTPUT_DIR}/${archive_name}" \
                    -C "$(dirname "$PROJECT_ROOT")" \
                        $(basename "$PROJECT_ROOT")/config \
                        $(basename "$PROJECT_ROOT")/.env.example 2>/dev/null || {
                    
                    log_error "Failed to create backup archive!"
                    exit 1
                    
                }
            }
        
        # Compute SHA256 checksum for integrity verification
        local checksum_file="${OUTPUT_DIR}/${archive_name}.sha256"
        cd "${OUTPUT_DIR}" && \
            sha256sum "${archive_name}" > "${checksum_file}" || {
            
            log_error "Failed to compute backup checksum!"
            exit 1
            
        }
        
    fi
    
}

# Function to verify backup integrity using stored checksums
verify_backup_integrity() {
    local archive="${OUTPUT_DIR}/arr-stack-config-*.tar.gz"
    
    if [ -z "$(ls -A "${OUTPUT_DIR}"/*.sha256 2>/dev/null)" ]; then
        log_warn "No .sha256 files found. Skipping integrity verification."
        return 0
        
    fi
    
    cd "${OUTPUT_DIR}" && \
        sha256sum -c *.sha256 2>&1 | while read line; do
            
            if echo "$line" | grep -q "OK"; then
                log_check "$(echo $line | awk '{print \$1}')"
            else
                log_error "$(echo $line)"
                
            fi
        
        done || true
    
    # Count verified backups
    local total=$(ls "${OUTPUT_DIR}"/*.sha256 2>/dev/null | wc -l)
    local passed=$(cd "${OUTPUT_DIR}" && sha256sum -c *.sha256 >/dev/null 2>&1; echo $? || echo "0")
    
    if [ "$passed" = "0" ]; then
        log_check "All ${total} backup(s) verified successfully!"
        
    else
        local failed=$((total - passed))
        if [ "$failed" != 0 ] && [ "$failed" != "" ]; then
            log_error "${failed} backup verification failure(s)! Check logs for details."
            
        fi
        
    fi
    
}

# Function to clean old backups based on retention policy (optional)
cleanup_old_backups() {
    if ! command -v find &> /dev/null; then
        return 0
    fi
    
    # Find and remove backups older than retention period
    local deleted_count=0
    
    while IFS= read -r old_backup; do
        log_warn "Removing expired backup: $(basename "$old_backup")"
        
        if [ ! "$DRY_RUN" = true ]; then
            rm -f "${old_backup}" && \
                sha256sum "${old_backup}.sha256" 2>/dev/null | awk '{print \$1}' > /dev/null || {
                
                    # Remove orphaned checksum file if backup was deleted but checksum still exists
                    
                }
            
            ((deleted_count++))
        fi
        
    done < <(find "${OUTPUT_DIR}" -name "arr-stack-config-*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS} 2>/dev/null)
    
    log_info "Cleaned up ${deleted_count} expired backup(s)" || true
    
}

# Function to display backup statistics
show_backup_stats() {
    echo ""
    echo "--- Backup Statistics ---"
    
    if [ -d "${OUTPUT_DIR}" ]; then
        local total_backups=$(ls -1 "${OUTPUT_DIR}/arr-stack-config-*.tar.gz" 2>/dev/null | wc -l)
        
        log_info "Total backups: ${total_backups:-0}"
        
        # Show newest backup info if exists
        if [ "$total_backups" != "" ] && [ "$total_backups" != "0" ]; then
            local latest=$(ls -t "${OUTPUT_DIR}/arr-stack-config-*.tar.gz" 2>/dev/null | head -1)
            
            log_info "Latest backup: $(basename "$latest")"
            
            if command -v du &> /dev/null; then
                local size=$(du -h --max-depth=0 "${OUTPUT_DIR}"/*.tar.gz 2>/dev/null | tail -1 | awk '{print \$1}')
                log_info "Total backup storage: ${size:-unknown}"
                
            fi
            
        else
            log_warn "No backups found yet."
            
        fi
        
    else
        log_warn "Backup directory does not exist or is empty."
        
    fi
    
}

# Main backup logic
main() {
    echo "=========================================="
    echo "ARR Media Stack Backup Script"
    echo "=========================================="
    
    # Ensure output directory exists
    ensure_backup_directory || true
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Dry run mode - no changes will be made"
        
        create_backup_tarball
        
        show_backup_stats
        
        echo ""
        log_info "Dry run complete. No backups were created."
        
    else
        # Create backup archive
        create_backup_tarball || exit 1
        
        # Verify integrity of newly created backup
        verify_backup_integrity
        
        # Show statistics (optional, can be enabled via flag)
        show_backup_stats
        
        log_info "Backup completed successfully!"
        
    fi
    
}

# Run main function with arguments
main "$@"
