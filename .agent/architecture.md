# Summary

This architecture defines a modular, Docker Compose-based media automation stack centered on the ARR (Automatic Requesting) ecosystem and Jellyfin. It implements strict network isolation via Gluetun for BitTorrent traffic using Proton VPN WireGuard, ensuring qBittorrent cannot bypass the tunnel or access the public internet directly when the VPN is unavailable. The design separates core services from optional components through Compose profiles, manages secrets exclusively at runtime without Git exposure, and enforces a consistent `/data` layout to minimize file copying during media imports via hardlinks where supported.

The solution relies on declarative configuration stored in `config/`, reproducible environment variables defined in `.env.example`, and automated scripts for health checks, backups, and verification. It supports hardware transcoding as an optional feature without compromising stability on CPU-only hosts. The architecture prioritizes security boundaries by restricting container privileges, isolating networks logically (Media, Download, Internal), and preventing unnecessary cross-service connectivity.

# Requirements interpretation

The specification outlines a complex stateful application requiring strict isolation between download traffic and media serving. Key architectural implications include:

| Requirement | Architectural Implication |
| :--- | :--- |
| **VPN Kill-Switch** | qBittorrent must be bound to the Gluetun network namespace; no direct host routing allowed for torrent containers. A healthcheck script verifies connectivity only through the VPN IP range or specific DNS resolution via Gluetun. |
| **Modular Services** | Core services (ARR, Jellyfin) are defined in `compose.yaml`. Optional services (Readarr, Grafana) must be loaded via a separate profile (`docker compose -p optional --profile core`) to avoid dependency coupling and ensure clean startup of the base stack. |
| **Hardlink Optimization** | The `/data` layout separates torrents from media. Services like Sonarr/Radarr write metadata; actual file movement should utilize `cp --archive` or hardlinks (`ln`) if supported by the filesystem (e.g., Btrfs/ZFS), avoiding unnecessary data duplication across containers. |
| **Secrets Management** | All sensitive data (VPN keys, API tokens) must be injected via Docker secrets or runtime environment variables passed to an orchestrator script. The `secrets/` directory contains only a `.gitkeep`. No placeholders for passwords exist in the repo. |
| **Reproducibility** | Configuration is code (`config/*.yaml`). Images use pinned tags (e.g., `ghcr.io/devopsfactory/gluetun:latest-ubuntu2404`) rather than floating tags to ensure deterministic builds across different host environments. |
| **Network Segmentation** | Three distinct networks are required: `download_net` (qBittorrent <-> Glueturn), `app_net` (ARR services, Jellyseerr), and `media_net` (Jellyfin). This prevents qBittorrent from resolving public IPs directly or leaking traffic. |
| **Backup Strategy** | Backups target configuration directories (`/data/config`) rather than media files by default. The backup script must verify checksums of the tarball before storing it off-host to ensure integrity without consuming excessive I/O bandwidth on slow storage arrays. |

# Proposed architecture

The system consists of a primary Docker Compose stack and an optional overlay for additional services. All containers run in user namespaces with restricted capabilities (`--cap-drop=ALL`, `--security-opt=no-new-privileges`).

### Container Topology
1.  **Gluetun**: Acts as the gateway proxy (WireGuard). It holds the active VPN connection. qBittorrent connects to this container's internal IP, not the host network directly.
2.  **qBittorrent**: Runs inside a Docker Compose profile or linked service that binds strictly to `gluetun`. Its configuration points to Gluetun as the download client. It listens on an internal port (e.g., 8091) accessible only via the application network, not exposed publicly by default.
3.  **ARR Services**: Sonarr, Radarr, Lidarr run in a shared `app_net`. They connect to Prowlarr for indexers and qBittorrent for downloads using internal IPs. Bazarr connects to these services for subtitle processing. Recyclarr runs as an external tool or container that reads/writes configuration files directly into the volume mounts of ARR services, ensuring declarative state management without relying on API calls during startup.
4.  **Jellyfin**: Runs in a separate network segment (`media_net`) but shares volumes with `app_net` for media access (via bind mount). It exposes port 8096 locally or via reverse proxy if needed. Hardware transcoding is enabled conditionally based on host GPU detection scripts during initialization, falling back to software decoding otherwise.
5.  **Jellyseerr**: Connects to Sonarr/Radarr APIs within `app_net` and serves the UI for user requests.

### Data Flow
1.  User Request -> Jellyseerr (UI/API) -> Radarr/Sonarr API.
2.  ARR Service finds torrent via Prowlarr Indexer -> Sends download command to qBittorrent.
3.  Gluetun routes traffic through Proton VPN tunnel -> Download completes in `/data/torrents/incomplete`.
4.  Post-processing (Renaming/Import) moves file from incomplete folder to `/data/media/[category]` using hardlinks or copy-on-write mechanisms if supported by the filesystem.

### Storage Layout (`/srv/media`)
*   **Torrents**: Stored in `torrents/{movies, tv, music}` for isolation and easy cleanup of failed downloads.
*   **Media Library**: Stored in `media/{movies, tv, music}` where Jellyfin serves content.
*   **Config**: All application configs reside under `/srv/media-stack/config`.

# Project structure

```text
arr-stack/
├── README.md                 # Minimal path to running stack
├── SPEC.md                   # Requirements document (source of truth)
├── LICENSE
├── Makefile                  # Build, test, deploy targets
├── compose.yaml              # Core services definition
├── compose.dev.yaml          # Development overrides (optional ports/debugging)
├── compose.test.yaml         # Test environment configuration
│
├── .env.example              # Template for non-secret env vars
├── .gitignore                # Excludes secrets, logs, data volumes
│
├── config/                   # Declarative service configurations
│   ├── gluetun/             # WireGuard configs, DNS settings
│   ├── qbittorrent/         # Torrent client settings (no passwords)
│   ├── sonarr/              # Quality profiles, download paths
│   ├── radarr/              # Movie quality rules
│   ├── lidarr/              # Music library config
│   ├── prowlarr/            # Indexer definitions
│   ├── bazarr/              # Subtitle language packs
│   ├── jellyfin/            # Library mappings, transcode settings
│   ├── jellyseerr/          # User management, API keys (placeholder)
│   └── recyclarr/           # Quality profile templates
│
├── data/                     # Persistent storage mounts
│   ├── torrents/            # Download queue and incomplete files
│   │   ├── movies
│   │   ├── tv
│   │   └── music
│   └── media/               # Final library for Jellyfin
│       ├── movies
│       ├── tv
│       └── music
│
├── secrets/                  # Runtime secret injection point (.gitkeep)
│   └── .gitkeep             # Placeholder to ensure directory exists
│
├── scripts/                  # Automation logic
│   ├── bootstrap.sh         # Initial setup, volume creation checks
│   ├── healthcheck.sh       # Verify container status and network isolation
│   ├── backup.sh            # Tar configuration + checksums
│   └── restore.sh           # Restore config from tarball
│   └── verify-vpn.sh        # Test kill-switch functionality
│
├── tests/                    # Automated test suites
│   ├── smoke/               # Basic container startup checks
│   ├── network/             # VPN routing and isolation verification
│   ├── security/            # Privilege escalation attempts, secret leakage check
│   └── integration/         # End-to-end ARR -> Jellyfin flow tests
│
├── docs/                     # Technical documentation
│   ├── architecture.md      # High-level design overview
│   ├── networking.md        # Network segmentation details
│   ├── storage.md           # Hardlink vs Copy strategy explanation
│   ├── security.md          # Security boundary definitions
│   └── backup.md            # Backup and restore procedures
│
└── .github/                  # CI/CD workflows (optional)
    └── workflows/           # Automated testing pipelines
```

# Components

### Gluetun
*   **Responsibility**: WireGuard VPN gateway. Routes all traffic for qBittorrent through ProtonVPN. Handles DNS resolution to prevent leaks.
*   **Dependencies**: Host network interface (via `--network host` or bridge with specific routing), Docker socket access only if required by image, but preferably managed via environment variables passed from orchestrator.
*   **Storage**: `/config/wireguard.conf`, `/data/secrets`.

### qBittorrent
*   **Responsibility**: BitTorrent client. Manages download queue and metadata fetching (via Prowlarr).
*   **Dependencies**: Gluetun network namespace (`--network gluetun_net`). No direct host networking allowed unless explicitly configured for specific use cases (not recommended by default).
*   **Storage**: `/data/torrents/incomplete`, `/config/qBittorrent`.

### Sonarr / Radarr / Lidarr
*   **Responsibility**: Media management. Monitor indexers, trigger downloads via qBittorrent API, handle renaming and importing to media folders.
*   **Dependencies**: Prowlarr (indexer config), qBittorrent (download client).
*   **Storage**: `/config/{service}`, `/data/media`.

### Bazarr
*   **Responsibility**: Subtitle management for Sonarr/Radarr imports. Fetches subtitles from providers and renames files to match media metadata.
*   **Dependencies**: Sonarr, Radarr APIs (internal network).
*   **Storage**: `/config/bazarr`, `/data/media`.

### Prowlarr
*   **Responsibility**: Centralized indexer management. Aggregates indexers from various providers and exposes a unified API to ARR services.
*   **Dependencies**: None external by default (can connect to ProtonVPN via Gluetun if needed, but usually runs on host network or internal bridge).

### Jellyfin
*   **Responsibility**: Media server for playback. Serves movies, TV shows, music from `/data/media`. Supports hardware transcoding when GPU is detected and configured in `config/jellyfin/extra.conf` (optional).
*   **Dependencies**: None external by default; reads media files directly via bind mount.

### Jellyseerr
*   **Responsibility**: User request management interface. Connects to Sonarr/Radarr APIs to create requests based on user input or queue items.
*   **Dependencies**: Sonarr, Radarr internal network.

### Recyclarr
*   **Responsibility**: Declarative configuration tool for ARR services (Sonarr/Radarr/Lidarr). Reads YAML files from `config/recyclarr/` and updates service settings without requiring API calls during runtime. Ensures reproducible quality profiles.

# Interfaces

| Interface | Protocol | Port | Direction | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Jellyfin UI** | HTTP | 8096 (Local) / Custom | Outbound to Host | Public access for media playback. Exposed only if explicitly enabled in config. |
| **qBittorrent WebUI**| HTTP | 8081 (Internal) | Inbound from ARR services | Download client management and API calls by Sonarr/Radarr/Lidarr. Not exposed publicly. |
| **Jellyseerr UI** | HTTPS/HTTP | Custom | Outbound to Host | User-facing request interface. Exposed locally or via reverse proxy. |
| **ARR APIs** | HTTP | 8989 (Sonarr), etc. | Internal Network Only | Communication between Jellyseerr, Bazarr, and ARR services within `app_net`. |
| **Prowlarr API** | HTTPS/HTTP | Custom | Inbound from ARR services | Indexer configuration retrieval for Sonarr/Radarr/Lidarr. |
| **Gluetun WireGuard**| UDP/TCP | 51820 (Host) | Outbound to Internet | Encrypted tunnel traffic routed through ProtonVPN servers. No public exposure of qBittorrent ports here; only Gluetun's interface is reachable from the host network if needed for management, but ideally isolated. |
| **Backup API** | N/A | File System | Internal Script Access | Scripts read/write to `/data/config` and external backup storage locations defined in `backup.sh`. |

# Security considerations

1.  **Network Isolation**: qBittorrent is strictly bound to the Gluetun network namespace (`--network gluetun_net`). It cannot resolve public IPs directly or leak traffic via DNS leaks because all DNS queries are routed through Gluetun's internal container, which uses ProtonVPN for resolution.
2.  **Privilege Escalation Prevention**: All containers run with `user: "1000:1000"` (UID/GID from host) and drop unnecessary capabilities (`--cap-drop=ALL`). The Docker socket is never mounted unless explicitly required by a specific service, which it isn't for this stack.
3.  **Secrets Handling**: Secrets are injected via `docker secrets` or environment variables passed at runtime to the orchestrator script. No hardcoded credentials exist in `.env.example`. The `secrets/` directory contains only a placeholder file (`.gitkeep`).
4.  **Kill-Switch Verification**: A dedicated healthcheck (`verify-vpn.sh`) runs periodically and immediately after container startup. It attempts to resolve public IPs via DNS; if the result does not match expected private ranges or fails, qBittorrent is considered non-functional until Gluetun reconnects successfully.
5.  **Least Privilege Access**: Containers do not have access to host filesystem paths outside of explicitly mounted volumes (`/data`, `/config`). Host firewall rules are modified only via explicit scripts authorized by the operator (e.g., `ufw` commands in a dedicated script).

# Testing strategy

### Configuration Tests
*   **Validation Script**: Runs `docker compose config` on every commit to ensure YAML syntax is valid and environment variables match expected types.
*   **Env Check**: A shell script verifies that required secrets are present (or marked as missing) before attempting startup, failing the build if critical vars like VPN keys or API tokens are absent from runtime envs.

### Startup Tests
*   **Smoke Test**: Starts all core containers and waits for healthchecks to pass (`docker compose up -d --wait`). Logs are inspected for "healthy" status indicators defined in `compose.yaml`.
*   **Restart Policy Check**: Simulates a crash by killing a container; verifies that the service restarts automatically without data loss.

### Network Tests
*   **VPN Isolation Test**: Uses Python or Curl scripts to verify qBittorrent's public IP matches Gluetun's assigned VPN IP, not the host's local LAN IP.
*   **DNS Leak Check**: Queries a known DNS leak test site (e.g., `dnsleaktest.com`) via qBittorrent; expects only ProtonVPN server locations to be returned.

### Integration Tests
*   **ARR Communication Test**: Sends a request from Jellyseerr to Sonarr/Radarr APIs and verifies the response code is 200 OK or appropriate error handling occurs if rate-limited.
*   **Media Access Check**: Verifies that Jellyfin can read files in `/data/media` without permission errors (UID/GID mismatch).

### Persistence Tests
*   **Recreation Test**: Stops all containers, removes volumes (`docker compose down -v --rmi local`), and restarts using `compose.yaml`. Confirms configuration data persists correctly.

# Deployment considerations

The deployment topology assumes a single host running Ubuntu with Docker installed. The stack is deployed via an orchestrator script that:
1.  Validates the environment (Docker version, disk space).
2.  Mounts volumes from `/srv/media` to container paths defined in `compose.yaml`.
3.  Injects secrets into containers using Docker's native secret mechanism or equivalent runtime injection methods supported by the orchestration layer.

**Upgrades**: The stack supports rolling updates via image version pinning. When a new image tag is pulled, existing volumes are preserved automatically due to bind mounts and named volumes defined in `compose.yaml`. No manual intervention is required for minor upgrades; major version changes may require configuration migration scripts if API endpoints change significantly (e.g., Jellyfin 10.x vs 9.x).

**Persistence**: Media files stored in `/data/media` are persistent across container restarts. Configuration data resides in `/config`, which is also persisted via bind mounts or named volumes depending on the service's requirements. Backups of configuration directories should be performed regularly using `backup.sh`.

# Assumptions

1.  **Host Environment**: The host runs Ubuntu (20.04 LTS or newer) with Docker Engine installed and configured to allow user namespace remapping (`userns-remap=default`).
2.  **Storage Backend**: The underlying filesystem supports hardlinks (e.g., ext4, XFS, Btrfs). If the storage is ZFS, `cp --archive` may be used instead of hardlinking for compatibility with certain services that do not support hardlinks natively.
3.  **Network Connectivity**: The host has a stable internet connection to download images and initial configuration files before deployment begins. ProtonVPN credentials are assumed to be provided securely via the orchestrator's secret management system, not stored in Git history.
4.  **Hardware Transcoding**: If hardware transcoding is enabled (via `config/jellyfin/extra.conf`), the host must have a compatible GPU driver installed and accessible within Docker (`--gpus all`). Without this flag or configuration, Jellyfin defaults to software decoding only.

# Open questions

1.  Should ProtonVPN port forwarding be implemented as an optional feature requiring specific firewall rules on the host (e.g., `iptables`/`nftables`) that might conflict with other network setups?
2.  Is there a preference for storing backup archives locally within `/data/backups` or off-host to external storage (S3, NAS)? The current design assumes local backups unless specified otherwise in future iterations.

# Implementation plan

1.  **Repository Initialization**: Create the directory structure as defined above. Initialize Git repository with `.gitignore` excluding `secrets/`, logs/, and data volumes.
2.  **Core Configuration Setup**: Write initial configurations for Gluetun, qBittorrent, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Jellyfin, Jellyseerr, and Recyclarr in the respective folders under `config/`. Use placeholder values where secrets are required but instruct users to inject them via runtime variables.
3.  **Compose File Creation**: Generate `compose.yaml` defining core services with appropriate networks (`app_net`, `download_net`) and volume mounts pointing to `/data/torrents` and `/data/media`. Add healthchecks for each service using official Docker Compose syntax or custom scripts if necessary.
4.  **Scripting Automation**: Implement `bootstrap.sh` (volume creation, initial config generation), `backup.sh` (tar + checksum), `restore.sh`, and `verify-vpn.sh`. Ensure these scripts are idempotent and handle errors gracefully.
5.  **Testing Integration**: Add test cases to the CI/CD pipeline or local testing suite (`tests/smoke`, `tests/network`). Verify that all tests pass on a clean Ubuntu host before marking as ready for production use.
6.  **Documentation Finalization**: Update README.md with installation steps, troubleshooting guides, and security notes. Ensure documentation covers how to add optional services via profiles without modifying core architecture.