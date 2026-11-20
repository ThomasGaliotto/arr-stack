# Storage Architecture

This document describes the storage layout and data management strategy for the ARR Media Stack.

## Directory Structure

```text
/data/
├── torrents/          # Download queue (incomplete files)
│   ├── incomplete/    # Active downloads in progress
│   ├── movies/        # Movie torrent metadata/downloads  
│   ├── tv/            # TV series torrent metadata/downloads
│   └── music/         # Music album torrent metadata/downloads
└── media/             # Final library for Jellyfin serving
    ├── movies/        # Imported and organized movie files
    ├── tv/            # Imported and organized TV show seasons
    └── music/         # Imported and organized music albums
```

## Volume Mounting Strategy

### Bind Mounts (Recommended)

The stack uses bind mounts from host filesystem to container paths:

- `/data/torrents/*` → Container torrent directories  
- `/data/media/*` → Container media library directories
- `/config/*` → Service configuration files

**Benefits**:
1. Direct access to host storage without copying data between containers
2. Enables hardlink optimization when filesystem supports it (Btrfs/ZFS)
3. Reduces I/O overhead during torrent downloads and imports
4. Simplifies backup strategy - only config needs regular backups, media can be backed separately

### Named Volumes (Fallback)

For services that don't support bind mounts well:
- `qbittorrent_config` → qBittorrent settings  
- `sonarr_config`, etc. → ARR service configs
- `jellyfin_config` → Jellyfin database and cache

## Hardlink Optimization Strategy

When the underlying filesystem supports hardlinks (ext4, XFS, Btrfs), use them to avoid data duplication:

```bash
# After torrent download completes in /data/torrents/incomplete/
# Move file from incomplete folder to media library using hardlink if possible

if [ -d "/dev/btrfs-control" ]; then  # Check for btrfs filesystem
    ln /path/to/file.incomplete /path/to/media/library/hardlinked-file
else
    cp --archive /path/to/file.incomplete /path/to/media/library/copy-of-file
fi
```

**Why hardlinks?**
1. Single file on disk, multiple references (saves space)
2. Faster than copying large files  
3. Atomic rename operation for import process
4. Consistent with ARR services' expectations about media paths

## Data Persistence Strategy

### What Persists Across Container Recreation

- `/data/torrents/*` - Download queue and incomplete torrents
- `/data/media/*` - Final library (Jellyfin serving)  
- All `config/` directories - Service configurations, databases, cache

### What Does NOT Persist Automatically

- Media files in `/data/media/*` are persistent via bind mount but should be backed up separately if needed
- Torrent metadata is stored within container volumes and persists with named volumes or host paths

## Backup Strategy

### Configuration Backups (Automated)

The `backup.sh` script creates tarballs of:
- All service configurations (`config/`)  
- `.env.example` template
- Recyclarr quality profiles
- Jellyfin configuration files
- Prowlarr indexer definitions

**Excluded from backups**:
- `/data/media/*` - Media library (too large, backup separately if needed)
- `/data/torrents/incomplete/*` - Active downloads (will be re-downloaded anyway)

### Restore Process

The `restore.sh` script can restore configurations from tarballs:
1. Validates backup integrity with SHA256 checksums  
2. Extracts configuration files to target directory
3. Preserves media library unchanged
4. Can overwrite existing configs if needed (use caution!)

## Storage Best Practices

### Host Directory Setup

```bash
# Create host directories before deployment
sudo mkdir -p /srv/media/{torrents,incomplete,movies,tv,music}
sudo mkdir -p /srv/media-stack/config
sudo chown $UID:$GID /srv/media /srv/media-stack/config
```

### Permissions Management

Ensure all data directories are owned by the same UID/GID:

```bash
# Set consistent ownership (adjust for your user)
chown 1000:1000 -R /data/torrents/
chown 1000:1000 -R /data/media/
chmod 755 -R /srv/media-stack/config/
```

### Disk Space Monitoring

Monitor disk usage regularly, especially for `/data/torrents/incomplete`:

```bash
# Check incomplete downloads (may indicate stuck torrents)
du -sh /data/torrents/incomplete/* | sort -h

# Monitor total storage usage  
df -h /srv/media/
```

### Cleanup Strategy

Periodically clean up:
- Failed torrent files in `/data/torrents/incomplete` that won't complete
- Old backup archives beyond retention policy (configurable via `BACKUP_RETENTION_DAYS`)
- Jellyfin cache if disk space is constrained

## Filesystem Considerations

### Recommended Filesystems

1. **Btrfs/ZFS**: Full support for hardlinks, snapshots, and efficient storage
2. **ext4/XFS**: Standard Linux filesystems with good performance  
3. **NFS/SMB**: Possible but may have permission issues - test thoroughly before use

### Avoid These Configurations

- Network shares without proper permissions (causes container startup failures)
- Filesystems that don't support hardlinks (may require copy instead, slower for large files)
- Storage with aggressive garbage collection (can cause data loss during active downloads)
