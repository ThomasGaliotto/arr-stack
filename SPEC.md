# ARR Media Stack

## Objective

Create a reproducible local Docker-based media automation stack built around the ARR ecosystem.

The stack must provide:

* Automated TV series management.
* Automated movie management.
* Automated music management.
* Indexer management.
* Subtitle management.
* BitTorrent downloading.
* Proton VPN network isolation for BitTorrent traffic.
* Media serving through Jellyfin.
* User requests through Seerr.
* Declarative quality/profile configuration.
* Persistent storage.
* Backup and restore capabilities.
* Automated health, security, integration and verification tests.

The project must be designed to be implemented and operated by a multi-agent AI orchestrator.

The implementation must be modular so optional services can be enabled or disabled without modifying the core architecture.

---

## Requirements

### Core services

The project must provide the following Docker services:

* Gluetun
* qBittorrent
* Sonarr
* Radarr
* Lidarr
* Prowlarr
* Bazarr
* Seerr (successor of Jellyseerr)
* Jellyfin
* Recyclarr

### Optional services

The architecture must support optional services without requiring changes to the core stack.

The following services should be considered optional:

* Readarr
* Tdarr
* Autobrr
* Homepage
* Prometheus
* Grafana
* Loki
* Additional monitoring services

Optional services must be isolated in dedicated Compose profiles or equivalent configuration mechanisms.

---

## VPN requirements

Gluetun must provide the VPN gateway for qBittorrent.

Proton VPN must be supported through WireGuard.

qBittorrent must use Gluetun's network namespace.

The architecture must prevent qBittorrent from accessing the Internet directly when the VPN is unavailable.

The implementation must include a VPN kill-switch verification test.

The implementation must support Proton VPN port forwarding when available for the selected Proton VPN configuration.

The implementation must not expose qBittorrent directly to the public Internet by default.

VPN credentials and private keys must never be stored in Git.

---

## ARR requirements

### Sonarr

Sonarr must manage TV series.

It must support:

* Series monitoring.
* Season monitoring.
* Episode monitoring.
* Quality profiles.
* Download client integration.
* Automatic importing.
* Automatic renaming.
* Media organization.

### Radarr

Radarr must manage movies.

It must support:

* Movie monitoring.
* Quality profiles.
* Download client integration.
* Automatic importing.
* Automatic renaming.
* Media organization.

### Lidarr

Lidarr must manage music.

It must support:

* Artist monitoring.
* Album monitoring.
* Download client integration.
* Automatic importing.
* Automatic organization.

### Prowlarr

Prowlarr must provide centralized indexer management.

Prowlarr must be integrated with:

* Sonarr.
* Radarr.
* Lidarr.

Indexer configuration should be centralized wherever practical.

### Bazarr

Bazarr must provide automated subtitle management.

Bazarr must integrate with:

* Sonarr.
* Radarr.

Subtitle languages must be configurable.

### Recyclarr

Recyclarr must provide declarative configuration for ARR quality profiles and related settings.

Configuration must be reproducible from files stored in the repository.

---

## Media server requirements

Jellyfin must provide the media server.

Jellyfin must expose:

* Movies.
* TV shows.
* Music.

The media directories must be persistent.

The architecture must support hardware transcoding when available on the host.

Hardware-specific configuration must remain optional and must not prevent the stack from running on a host without a GPU.

---

## User request requirements

Seerr must provide a user-facing interface for requesting:

* Movies.
* TV series.

Seerr must integrate with:

* Radarr.
* Sonarr.

Requests must be forwarded to the appropriate ARR service.

---

## Storage requirements

The project must use a consistent `/data` layout.

The recommended structure is:

```text
/data
├── torrents
│   ├── incomplete
│   ├── movies
│   ├── tv
│   └── music
│
└── media
    ├── movies
    ├── tv
    └── music
```

All relevant services must use compatible paths.

The architecture must allow hardlinks when supported by the underlying filesystem.

The implementation must avoid unnecessary file copies during ARR imports.

Configuration data must be persistent.

Application data must survive container recreation.

---

## Docker requirements

The entire application stack must run inside Docker.

Docker Compose must be used as the primary orchestration mechanism.

The project must provide:

* `compose.yaml`
* `.env.example`
* `.gitignore`
* Persistent volumes or bind mounts.
* Healthchecks where supported.
* Restart policies.
* Explicit image versions wherever practical.

The stack must be reproducible from a clean checkout.

Containers must not modify the Ubuntu host outside explicitly configured storage locations.

---

## Network requirements

The project must define separate logical Docker networks where appropriate.

The architecture should provide at least:

* Media network.
* Download network.
* Internal/application network.

The network architecture must minimize unnecessary connectivity between services.

qBittorrent must communicate through Gluetun.

ARR services must be able to communicate with qBittorrent.

ARR services must be able to communicate with Prowlarr.

Sonarr and Radarr must be accessible by Seerr.

Jellyfin must be able to access the media library.

Services must not expose unnecessary ports.

All management interfaces must be local/LAN-only by default.

No service must be exposed directly to the public Internet by default.

---

## Configuration requirements

The project must provide a central configuration mechanism.

The configuration must support:

* Timezone.
* UID.
* GID.
* Data root.
* Configuration root.
* VPN provider.
* VPN protocol.
* VPN region/server selection.
* VPN port forwarding.
* Enabled services.
* Media types.
* Subtitle languages.

A configuration example must be provided.

Example:

```yaml
instance:
  name: home-media

host:
  data_root: /srv/media
  config_root: /srv/media-stack
  timezone: Europe/Brussels
  uid: 1000
  gid: 1000

vpn:
  provider: protonvpn
  protocol: wireguard
  country: Netherlands
  port_forwarding: true

media:
  movies: true
  tv: true
  music: true
  books: false
  subtitles: true

services:
  jellyfin: true
  jellyseerr: true
  sonarr: true
  radarr: true
  lidarr: true
  prowlarr: true
  bazarr: true
  recyclarr: true
  readarr: false
  tdarr: false
```

---

## Secrets requirements

Secrets must never be committed to Git.

The repository must contain only examples/placeholders.

The project must support secrets for:

* Proton VPN.
* WireGuard private key.
* ARR API keys where required.
* Seerr credentials/API keys where required.
* Other service credentials.

Secrets must not appear in:

* `compose.yaml`.
* `.env.example`.
* Git history.
* Documentation.
* Logs.
* Test artifacts.

Secrets generated by the services themselves should be generated automatically whenever possible.

The deployment process must stop at a dedicated `WAITING_FOR_SECRETS` state when a human-provided secret is required.

The deployment agent must clearly identify which secret is required and why.

The orchestrator must never ask the user for credentials that it can safely generate itself.

---

## Project structure

The project must use the following structure or an equivalent structure approved by the Architect agent:

```text
arr-stack/
├── README.md
├── SPEC.md
├── LICENSE
├── Makefile
├── compose.yaml
├── compose.dev.yaml
├── compose.test.yaml
│
├── .env.example
├── .gitignore
│
├── config/
│   ├── gluetun/
│   ├── qbittorrent/
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── prowlarr/
│   ├── bazarr/
│   ├── jellyfin/
│   ├── jellyseerr/
│   └── recyclarr/
│
├── data/
│   ├── torrents/
│   └── media/
│
├── secrets/
│   └── .gitkeep
│
├── scripts/
│   ├── bootstrap.sh
│   ├── healthcheck.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── verify-vpn.sh
│
├── tests/
│   ├── smoke/
│   ├── network/
│   ├── security/
│   └── integration/
│
├── docs/
│   ├── architecture.md
│   ├── networking.md
│   ├── storage.md
│   ├── security.md
│   ├── backup.md
│   └── operations.md
│
└── .github/
    └── workflows/
```

---

## Multi-agent requirements

The project must be designed for an AI orchestration workflow.

The orchestrator must support the following agents:

* Architect.
* Implementer.
* Code Reviewer.
* Security Reviewer.
* Tester.
* Deployer.
* Verifier.
* Final Reviewer.

Each agent must have a clearly defined responsibility.

Agents must communicate through structured artifacts rather than relying exclusively on natural-language context.

---

## Architect agent

The Architect agent must:

* Analyze the project specification.
* Produce the system architecture.
* Define services.
* Define networks.
* Define storage.
* Define dependencies.
* Identify security risks.
* Identify required secrets.
* Produce an implementation plan.

The Architect agent must not directly deploy the stack.

The architecture output must be machine-readable.

---

## Implementer agent

The Implementer agent must:

* Create Docker Compose configuration.
* Create configuration files.
* Create scripts.
* Create tests.
* Create documentation.
* Implement healthchecks.
* Implement backup/restore functionality.

The Implementer agent must not commit secrets.

The Implementer agent must not modify the Ubuntu host outside explicitly configured project paths.

---

## Code Reviewer agent

The Code Reviewer agent must review:

* Docker Compose configuration.
* Scripts.
* Configuration.
* Documentation.
* Tests.

The Code Reviewer must verify:

* Reproducibility.
* Correct dependencies.
* Correct volume mappings.
* Correct networking.
* Healthchecks.
* Restart policies.
* Version pinning.
* Configuration consistency.

The Code Reviewer must produce a PASS or FAIL result.

A FAIL result must include actionable findings.

---

## Security agent

The Security agent must verify:

* No secrets in the repository.
* No secrets in logs.
* No unnecessary exposed ports.
* No unnecessary Docker privileges.
* No unnecessary Linux capabilities.
* No unnecessary host mounts.
* No `privileged: true` unless explicitly justified.
* No Docker socket access unless explicitly justified.
* Correct network isolation.
* VPN kill switch.
* DNS leak protection.
* Container permissions.
* File permissions.
* Public exposure risks.

The Security agent must produce a machine-readable security report.

---

## Tester agent

The Tester agent must execute automated tests.

Tests must cover:

* Compose configuration.
* Container startup.
* Healthchecks.
* HTTP availability.
* Service connectivity.
* Storage persistence.
* VPN connectivity.
* VPN isolation.
* DNS behavior.
* Kill switch behavior.
* Backup.
* Restore.

Tests must be repeatable.

Tests must not require manual interaction unless explicitly documented.

---

## Deployer agent

The Deployer agent must:

* Validate the configuration.
* Validate required secrets.
* Prepare required directories.
* Start the Docker Compose stack.
* Wait for services to become healthy.
* Run deployment smoke tests.
* Report deployment status.

The Deployer agent must be idempotent.

Running the deployment multiple times must not corrupt existing configuration or media.

The Deployer agent must not silently overwrite existing user data.

---

## Verifier agent

The Verifier agent must validate the complete system from the outside.

It must verify the complete logical flow:

```text
Prowlarr
    ↓
Sonarr / Radarr / Lidarr
    ↓
qBittorrent
    ↓
Gluetun
    ↓
Proton VPN
    ↓
Download
    ↓
ARR Import
    ↓
Media Library
    ↓
Jellyfin
```

The Verifier must test service availability and integration.

The Verifier must verify that qBittorrent cannot bypass the VPN.

The Verifier must produce a final machine-readable verification report.

---

## Final Reviewer agent

The Final Reviewer must receive:

* Original specification.
* Architecture.
* Implementation.
* Code review.
* Security report.
* Test report.
* Deployment report.
* Verification report.

The Final Reviewer must identify specification drift.

The Final Reviewer must ensure that all acceptance criteria are satisfied.

The Final Reviewer must not approve the project when critical requirements remain unresolved.

---

## Orchestrator state machine

The orchestrator must support the following lifecycle:

```text
PLANNING
    ↓
ARCHITECTED
    ↓
IMPLEMENTING
    ↓
CODE_REVIEW
    ↓
SECURITY_REVIEW
    ↓
WAITING_FOR_SECRETS
    ↓
DEPLOYING
    ↓
TESTING
    ↓
VERIFYING
    ↓
FINAL_REVIEW
    ↓
ACCEPTED
```

Failures must return the project to the appropriate previous state.

Example:

```text
CODE_REVIEW
    ↓
FAIL
    ↓
IMPLEMENTING
```

```text
TESTING
    ↓
FAIL
    ↓
DEBUGGING
    ↓
IMPLEMENTING
```

The orchestrator must never mark the project as accepted when a required verification step has failed.

---

## Backup requirements

The project must provide automated backup functionality.

Backups must include:

* Service configuration.
* ARR configuration.
* Jellyfin configuration.
* Seerr configuration.
* Prowlarr configuration.
* qBittorrent configuration.
* Recyclarr configuration.
* Relevant secrets when explicitly configured by the operator.

Media files do not need to be included in configuration backups unless explicitly requested.

Backup scripts must verify backup integrity.

Restore scripts must be tested automatically.

---

## Observability requirements

The stack must provide enough information to diagnose failures.

The implementation must provide:

* Container status.
* Health status.
* Service logs.
* Deployment logs.
* Test reports.
* Verification reports.

Optional monitoring services may be implemented later.

---

## Documentation requirements

The repository must contain documentation covering:

* Installation.
* Configuration.
* Secrets.
* Networking.
* VPN setup.
* Storage.
* Service access.
* Backup.
* Restore.
* Troubleshooting.
* Updating.
* Adding optional services.
* Disaster recovery.

The README must provide a minimal path from a clean checkout to a running installation.

---

## Security constraints

The stack must run with the minimum privileges required.

Containers must not use privileged mode unless explicitly justified.

Containers must not access the host filesystem outside explicitly configured paths.

The Docker socket must not be mounted unless explicitly justified.

Secrets must not be embedded in images.

Secrets must not be committed to Git.

Services must not be exposed to the public Internet by default.

The VPN must provide a network boundary for BitTorrent traffic.

A VPN failure must not result in qBittorrent using the host's normal Internet connection.

---

## Host constraints

The agents must not modify the Ubuntu host outside explicitly configured project and data directories.

The agents must not:

* Modify system-wide firewall rules without explicit authorization.
* Modify system-wide DNS configuration without explicit authorization.
* Install arbitrary packages without explicit authorization.
* Modify unrelated Docker projects.
* Delete user data.
* Modify unrelated filesystems.

The project must operate through Docker wherever practical.

Any required host-level dependency must be documented before installation.

---

## Reproducibility constraints

A clean machine with the documented prerequisites must be able to recreate the stack.

The implementation must not depend on undocumented manual configuration.

Configuration must be stored as code wherever practical.

Generated configuration must be reproducible.

Images should use explicit versions rather than floating tags wherever practical.

The project must document any unavoidable external state.

---

## Testing requirements

The following test categories are mandatory:

### Configuration tests

* Docker Compose configuration validates.
* Required environment variables are detected.
* Invalid configuration fails clearly.

### Startup tests

* Containers start.
* Required containers become healthy.
* Restarting containers does not destroy configuration.

### Network tests

* qBittorrent uses the VPN.
* qBittorrent public IP is the VPN IP.
* qBittorrent cannot reach the Internet when Gluetun is stopped.
* DNS does not bypass the VPN.

### Integration tests

* Prowlarr can communicate with ARR services.
* Sonarr can communicate with qBittorrent.
* Radarr can communicate with qBittorrent.
* Lidarr can communicate with qBittorrent.
* Seerr can communicate with Sonarr.
* Seerr can communicate with Radarr.
* Jellyfin can read the media directories.

### Persistence tests

* Containers can be recreated.
* Configuration survives recreation.
* Media remains available.

### Backup tests

* Backup succeeds.
* Backup integrity can be verified.
* Restore succeeds.
* Restored services remain functional.

---

## Acceptance criteria

* The project contains a complete Docker Compose configuration.
* The stack starts successfully on a supported Ubuntu host.
* All core services have persistent configuration.
* qBittorrent runs through Gluetun.
* qBittorrent cannot bypass the VPN.
* Proton VPN connectivity is verified.
* VPN failure prevents qBittorrent Internet access.
* Sonarr is operational.
* Radarr is operational.
* Lidarr is operational.
* Prowlarr is operational.
* Bazarr is operational.
* Seerr is operational.
* Jellyfin is operational.
* Recyclarr configuration is reproducible.
* Media paths are consistently mapped.
* Required Docker networks are correctly configured.
* No unnecessary public ports are exposed.
* No secrets are committed to the repository.
* Required secrets are explicitly requested through the orchestrator when necessary.
* Healthchecks pass.
* Automated tests pass.
* Security review passes.
* Backup succeeds.
* Restore succeeds.
* Verification succeeds.
* Documentation is present.
* The deployment is reproducible.
* The deployment is idempotent.
* The final reviewer reports no unresolved critical findings.

---

## Required human inputs

The orchestrator must request human input only when required.

The following information may be requested during deployment:

* Proton VPN WireGuard configuration or required Proton VPN credentials.
* Preferred Proton VPN region/server.
* Host data directory.
* Host configuration directory.
* Linux UID/GID.
* Timezone.

The orchestrator must request these values at the appropriate deployment stage rather than requiring them before architecture and implementation work can begin.

Secrets must never be requested unnecessarily.

The orchestrator must pause in `WAITING_FOR_SECRETS` when a required secret cannot be generated automatically.

---

## Definition of done

The project is complete only when:

* Architecture is approved.
* Implementation is complete.
* Code review passes.
* Security review passes.
* Deployment succeeds.
* All core services are healthy.
* VPN isolation is verified.
* Integration tests pass.
* Persistence is verified.
* Backup is verified.
* Restore is verified.
* Final verification passes.
* Documentation is complete.
* No critical findings remain.
* The Final Reviewer marks the project as `ACCEPTED`.
