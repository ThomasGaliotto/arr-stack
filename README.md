# ARR Media Stack

A reproducible local Docker-based media automation stack built around the ARR (Automatic Requesting) ecosystem with Jellyfin as the media server, Proton VPN for BitTorrent traffic isolation via Gluetun.

## Quick Start

```bash
# 1. Prepare host directories
sudo mkdir -p /srv/media/{torrents,incomplete,movies,tv,music}
sudo mkdir -p /srv/media-stack/config
sudo chown $UID:$GID /srv/media /srv/media-stack/config

# 2. Configure environment variables (see .env.example)
cp .env.example .env
vi .env  # Edit with your values, especially VPN settings

# 3. Generate secrets if needed (orchestrator handles this in production)
# Secrets are injected at runtime - never commit to Git!

# 4. Start the stack
make deploy

# 5. Access services:
#    Jellyfin UI: http://localhost:8096
#    Seerr UI: http://localhost:8097 (if exposed)
```

## Architecture Overview

- **Core Services**: Gluetun, qBittorrent, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Recyclarr, Seerr, Jellyfin
- **Network Isolation**: Three networks (`download_net`, `app_net`, `media_net`) with strict separation
  - `download_net`: Gluetun + qBittorrent only (VPN traffic)
  - `app_net`: ARR services communication (Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Seerr/Recyclarr)
  - `media_net`: Jellyfin media server (internal, isolated from other networks)
- **VPN Kill-Switch**: Gluetun routes all qBittorrent traffic; no direct internet access when VPN unavailable
- **Secrets Management**: Runtime injection only via Docker secrets or environment variables - never committed to Git

## Directory Structure

```text
arr-stack/
├── README.md                 # This file
├── SPEC.md                   # Requirements (source of truth)
├── LICENSE
├── Makefile                  # Build/deploy targets
├── compose.yaml              # Core services definition
├── compose.dev.yaml          # Development overrides with profiles
├── compose.test.yaml         # Test environment configuration
├── .env.example              # Non-secret environment variables template
├── .gitignore                # Excludes secrets, logs, data volumes
│
├── config/                   # Declarative service configurations
│   ├── gluetun/             # WireGuard configs and settings
│   ├── qbittorrent/         # Torrent client settings (no passwords)
│   ├── sonarr/              # TV series configuration
│   ├── radarr/              # Movie configuration  
│   ├── lidarr/              # Music configuration
│   ├── prowlarr/            # Indexer definitions
│   ├── bazarr/              # Subtitle management config
│   ├── jellyfin/            # Media server settings
│   ├── jellyseerr/          # Request manager config
│   └── recyclarr/           # Quality profile templates and configs
│
├── data/                     # Persistent storage mounts (bind-mounted from host)
│   ├── torrents/            # Download queue and incomplete files
│   │   ├── movies
│   │   ├── tv
│   │   └── music
│   └── media/               # Final library for Jellyfin
│       ├── movies
│       ├── tv
│       └── music
│
├── secrets/                  # Runtime secret injection (.gitkeep only)
│   └── .gitkeep

├── scripts/                  # Automation logic
│   ├── bootstrap.sh         # Initial setup and volume checks
│   ├── healthcheck.sh       # Container status verification
│   ├── backup.sh            # Configuration backup with checksums
│   ├── restore.sh           # Restore from tarball
│   └── verify-vpn.sh        # VPN kill-switch functionality test

├── tests/                    # Automated test suites (to be implemented)
│   ├── smoke/               # Basic container startup checks
│   ├── network/             # VPN routing and isolation verification
│   ├── security/            # Privilege escalation attempts, secret leakage check
│   └── integration/         # End-to-end ARR -> Jellyfin flow tests

├── docs/                     # Technical documentation
│   ├── architecture.md      # High-level design overview
│   ├── networking.md        # Network segmentation details  
│   ├── storage.md           # Hardlink vs Copy strategy explanation
│   ├── security.md          # Security boundary definitions
│   └── backup.md            # Backup and restore procedures

├── .github/                  # CI/CD workflows (optional)
│   └── workflows/           # Automated testing pipelines
```

## Configuration Example

See `.env.example` for required environment variables. See `config/*.yaml` files for service-specific configurations.

Key configuration sections:
- **Host**: Data root, config root, UID/GID, timezone
- **VPN**: Provider (ProtonVPN), protocol (WireGuard), country/server region
- **Media**: Enable/disable movies/TV/music/books/subtitles
- **Services**: Enable/disable each service via environment variables

## Secrets Management

**IMPORTANT**: Never commit secrets to Git! The repository contains only placeholders in `.env.example`. All sensitive data must be injected at runtime:

Required secrets (injected by orchestrator):
- Proton VPN WireGuard private key (`/data/secrets/gluetun`)
- ARR service API keys where applicable  
- Seerr admin credentials/API keys if not auto-generated

Secrets are provided via:
1. Docker Compose secrets mechanism
2. Runtime environment variables from secure source
3. Orchestrator secret management system

## Deployment States

The deployment process follows these states managed by the orchestrator:

1. **PLANNING** - Architecture defined and approved
2. **ARCHITECTED** - Implementation plan created  
3. **IMPLEMENTING** - Files being created/modified (current state)
4. **CODE_REVIEW** - Configuration validated by Code Reviewer agent
5. **SECURITY_REVIEW** - Security audit completed
6. **WAITING_FOR_SECRETS** - Orchestrator pauses for required secrets
7. **DEPLOYING** - Stack started and healthchecks running
8. **TESTING** - Automated tests executed
9. **VERIFYING** - End-to-end verification complete
10. **FINAL_REVIEW** - Acceptance criteria validated
11. **ACCEPTED** - Project ready for production

## Backup & Restore

```bash
# Create backup (configuration only, not media files)
make backup

# Verify backup integrity  
make verify-backup

# Restore from backup
make restore BACKUP_FILE=/path/to/backup.tar.gz

# Dry run without making changes
./scripts/backup.sh --dry-run
```

## Adding Optional Services

Optional services like Readarr or monitoring tools are added via Docker Compose profiles:

```bash
# Enable optional services (if configured in compose.dev.yaml)
docker compose -p optional up -d readarr grafana loki

# Or add new service to compose.yaml directly
```

See `compose.dev.yaml` for profile examples.

## Network Architecture

The stack uses three isolated networks:

1. **download_net** (`arr-stack-download-net`)
   - Contains only Gluetun and qBittorrent
   - All traffic routed through ProtonVPN WireGuard tunnel
   - No direct internet access when VPN is unavailable (kill-switch)

2. **app_net** (`arr-stack-app-net`)  
   - ARR services: Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Seerr, Recyclarr
   - Internal communication between services only
   - Not exposed to public internet by default

3. **media_net** (`arr-stack-media-net`)
   - Contains only Jellyfin media server
   - Isolated from download and application networks for security
   - Accesses media files via bind mounts from host filesystem

## Security Features

- All containers run with `--cap-drop=ALL` and `no-new-privileges:true`
- qBittorrent uses `network_mode: service:gluetun` to share VPN namespace
- No Docker socket mounted unless explicitly required (not in default config)
- Secrets never stored in Git or compose files
- Network segmentation prevents lateral movement between services

## Troubleshooting

```bash
# Check container health status
make status

# View logs for specific service  
docker compose logs -f <service>

# Verify VPN isolation is working
./scripts/verify-vpn.sh --all-services

# Run all automated tests
make test-all

# Reboot stack (preserves data)
make reboot

# Check healthcheck results
./scripts/healthcheck.sh --all-services
```

## License

See LICENSE file for details.
