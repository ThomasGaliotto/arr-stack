#!/bin/bash
# =============================================================================
# ARR Media Stack - Restore Script
# =============================================================================
# This script restores configuration from a backup tarball.
# Usage: ./restore.sh <backup_path> [target_dir]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

BACKUP_FILE=""
TARGET_DIR="${1:-}"  # Optional target directory (defaults to /data/config)

usage() {
    echo "Usage: $0 <backup_path> [target_dir]"
    echo ""
    echo "Arguments:"
    echo "  backup_path   Path to the backup tarball (.tar.gz)"
    echo "  target_dir    Target directory for restore (default: /data/config)"
    echo ""
    echo "Examples:"
    echo "  $0 backups/latest.tar.gz"
    echo "  $0 /path/to/backup.tar.gz /srv/media-stack/config"
    exit 1
}

# Check if backup file is provided
if [[ -z "$BACKUP_FILE" ]]; then
    usage
fi

# Validate backup file exists
if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}" >&2
    exit 1
fi

echo "[INFO] Validating backup integrity..."

# Verify tarball is valid and readable
if ! tar -tzf "${BACKUP_FILE}" > /dev/null 2>&1; then
    echo "ERROR: Backup file appears to be corrupted or invalid" >&2
    exit 1
fi

echo "[INFO] Backup validation successful."

# Check if target directory exists, create if needed
TARGET_DIR="${TARGET_DIR:-/data/config}"
if [[ ! -d "${TARGET_DIR}" ]]; then
    echo "[WARN] Target directory does not exist: ${TARGET_DIR}" >&2
    mkdir -p "${TARGET_DIR}" || {
        echo "ERROR: Failed to create target directory" >&2
        exit 1
    }
fi

# Extract backup contents (excluding media files if present)
echo "[INFO] Restoring configuration from backup..."

# Create a temporary extraction directory
TEMP_EXTRACT=$(mktemp -d) || {
    echo "ERROR: Failed to create temporary extraction directory" >&2
    exit 1
}

trap 'rm -rf "${TEMP_EXTRACT}"' EXIT

# Extract the tarball
tar -xzf "${BACKUP_FILE}" -C "${TEMP_EXTRACT}" || {
    echo "ERROR: Failed to extract backup file" >&2
    exit 1
}

# Copy configuration files (excluding media data)
echo "[INFO] Restoring service configurations..."

CONFIG_DIRS=(
    "gluetun"
    "qbittorrent"
    "sonarr"
    "radarr"
    "lidarr"
    "prowlarr"
    "bazarr"
    "jellyfin"
    "jellyseerr"
    "recyclarr"
)

for dir in "${CONFIG_DIRS[@]}"; do
    SOURCE_DIR="${TEMP_EXTRACT}/${dir}"
    TARGET_SUBDIR="${TARGET_DIR}/${dir}"
    
    if [[ -d "${SOURCE_DIR}" ]]; then
        mkdir -p "${TARGET_SUBDIR}" || {
            echo "ERROR: Failed to create ${TARGET_SUBDIR}" >&2
            exit 1
        }
        
        # Copy files, preserving permissions where possible
        cp -a "${SOURCE_DIR}/"*.yaml "${TARGET_SUBDIR}/" 2>/dev/null || true
        
        if [[ $? -eq 0 ]]; then
            echo "[INFO] Restored configuration for: ${dir}"
        fi
    else
        echo "[WARN] No configuration found in backup for: ${dir} (skipping)"
    fi
done

# Restore recyclarr quality profiles specifically
if [[ -f "${TEMP_EXTRACT}/recyclarr/quality-profiles.yaml" ]]; then
    cp -a "${TEMP_EXTRACT}/recyclarr/quality-profiles.yaml" \
         "${TARGET_DIR}/recyclarr/" 2>/dev/null || true
fi

# Clean up temporary files (handled by trap)
echo "[INFO] Configuration restore complete."
echo ""
echo "Note: Media files in /data/media were NOT restored from this backup."
echo "      Only configuration data was restored to ${TARGET_DIR}"

exit 0
