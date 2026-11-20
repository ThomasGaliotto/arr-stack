# Security Overview

This document describes the security measures implemented in the ARR Media Stack.

## Container Hardening

All containers run with minimal privileges:

- `cap_drop: ALL` - Drop all Linux capabilities by default
- `security_opt: no-new-privileges:true` - Prevent privilege escalation
- No privileged mode unless explicitly justified
- User namespace remapping where supported

## Network Isolation

The stack uses three isolated Docker networks to minimize attack surface:

1. **download_net** (internal): Gluetun + qBittorrent only for VPN traffic
2. **app_net**: ARR services communication layer  
3. **media_net** (internal, internal: true): Jellyfin media server isolation

qBittorrent uses `network_mode: service:gluetun` to share the same network namespace as Gluetun, ensuring it cannot bypass the VPN or access public internet directly when VPN is unavailable.

## Secrets Management

Secrets are never committed to Git:

- WireGuard private key for ProtonVPN injected at runtime
- ARR API keys managed via Docker secrets or environment variables at deployment time
- Seerr admin credentials generated automatically or provided securely during setup

The `secrets/` directory contains only `.gitkeep` placeholder. Actual secret files are excluded from Git tracking via `.gitignore`.

## VPN Kill-Switch

Gluetun is configured with `BLOCK_OUTSIDE_VPN_NETWORKS=true`, which blocks all traffic when the VPN connection fails or is unavailable, preventing qBittorrent from leaking torrent data to untrusted networks.

## DNS Leak Protection

Gluetun uses trusted DNS servers (1.1.1.1 and 8.8.8.8) that respect privacy policies:
- Cloudflare DNS (1.1.1.1): Privacy-respecting resolver
- Google DNS (8.8.8.8): Fallback option

## Volume Mount Restrictions

Containers only access explicitly mounted volumes:

- `/data/media/*` - Media library directories
- `*_config:/config` - Service configuration directories
- No host filesystem mounts outside these paths
- Read-only mount for WireGuard private key in Gluetun (`/etc/wireguard/private.key:ro`)

## Port Exposure Policy

By default, no ports are exposed to the public Internet. Services communicate via internal Docker networks only. User-facing services (Seerr) can be exposed locally or behind a reverse proxy as needed.

## Restart Policies

All containers use `restart: unless-stopped` for automatic recovery from failures without manual intervention.
