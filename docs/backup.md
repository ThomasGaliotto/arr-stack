# Backup Overview

This document describes the backup functionality for the ARR Media Stack.

## What Gets Backed Up

The following configuration data is included in backups (media files are excluded by default):

- Service configurations (`config/*`)
- Sonarr/Radarr/Lidarr settings and metadata databases
- Prowlarr indexer configurations  
- Bazarr subtitle preferences
- Seerr queue and user settings
- Jellyfin library mappings and cache data
- qBittorrent download list (optional)
- Recyclarr quality profiles

## What Does NOT Get Backed Up By Default

Media files in `/data/media/*` are excluded from configuration backups. These should be backed up separately using your preferred media backup solution.

Torrent metadata for completed downloads may optionally be included if configured.

## Backup Script Usage

```bash
# Run full backup with gzip compression
./scripts/backup.sh --compress=gzip

# Dry-run to see what would be backed up
./scripts/backup.sh --dry-run

# Specify custom retention period (default: 30 days)
BACKUP_RETENTION_DAYS=60 ./scripts/backup.sh
```

## Backup Location

Backups are stored in a dedicated directory outside the main data root. The default location is configurable via `HOST_CONFIG_ROOT`.

## Restore Process

The restore script can recover configurations from backup files:

```bash
# Full configuration restore (media files untouched)
./scripts/restore.sh --source=/path/to/backup.tar.gz

# Verify backup integrity before restoring
./scripts/verify-vpn.sh  # Also verifies other system health checks
```

## Backup Verification

The backup script includes integrity verification:

- File count validation against manifest
- Checksum verification for compressed archives  
- Size consistency checks
- Optional test restore to temporary location

## Retention Policy

Configure `BACKUP_RETENTION_DAYS` in `.env.example`:

- Default: 30 days
- Adjust based on storage availability and compliance requirements
- Old backups are automatically cleaned up during backup runs
