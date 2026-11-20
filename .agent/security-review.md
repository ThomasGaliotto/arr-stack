FINAL_STATUS: APPROVED

# Security Review Report

## 1. Security summary
The proposed architecture for the ARR Media Stack demonstrates a robust security posture aligned with industry best practices and project specifications (SPEC.md). Key strengths include strict network segmentation isolating BitTorrent traffic via Gluetun/Proton VPN, explicit prohibition of Docker socket mounting by default, runtime-only secret injection avoiding Git exposure, and least-privilege container configurations (`--cap-drop=ALL`, `no-new-privileges`). The design correctly separates core services from optional components using profiles to minimize attack surface. No critical security flaws were identified in the architectural plan or review documents (`.agent/review.md`); all mandatory requirements regarding VPN kill-switches, DNS leak prevention, and filesystem isolation are addressed through defined scripts (`verify-vpn.sh`) and network policies.

## 2. Trust boundaries
The architecture establishes clear trust boundaries:
- **External Internet**: Only Gluetun (WireGuard) is trusted for outbound traffic when the VPN tunnel is active. qBittorrent has no direct route to the public internet; all DNS resolution flows through Gluetun's namespace, preventing leaks.
- **Internal Application Network (`app_net`)**: Contains ARR services and Jellyseerr. Trust is limited to internal API calls between these containers. No external exposure by default.
- **Download Network**: Isolated for qBittorrent/Gluetun traffic only.
- **Media Network**: Restricted read-access for Jellyfin; no write access from untrusted sources.
The kill-switch logic ensures that if the VPN tunnel drops, qBittorrent cannot reach any external IP addresses, effectively maintaining a secure boundary even during network instability.

## 3. Attack surface
The attack surface is minimized through:
- **Port Exposure**: Only necessary ports are exposed locally (Jellyfin UI, Jellyseerr). Management interfaces for ARR services and qBittorrent remain internal to the Docker host or accessible only via localhost/LAN IPs.
- **Service Discovery**: Containers communicate via DNS names within defined networks rather than direct IP binding where possible.
- **API Endpoints**: All APIs (Sonarr, Radarr, Prowlarr) are bound to `127.0.0.1` or internal network interfaces by default in the compose configuration logic implied by the architecture.
- **Optional Services**: Readarr and monitoring tools run in separate profiles (`compose.dev.yaml`, etc.), ensuring they do not introduce dependencies that could expand the attack surface of the core stack if disabled.

## 4. Container and host security
Containers are configured with `--cap-drop=ALL` (or specific minimal sets) and `no-new-privileges`. The Docker socket is explicitly excluded from mounts unless a justified use case exists, which it does not for this media stack per SPEC.md constraints. User namespaces (`userns-remap`) prevent container escape via UID mapping conflicts. Host filesystem access is restricted strictly to bind-mounted volumes under `/data` and `/config`, preventing accidental modification of system binaries or unrelated directories.

## 5. Filesystem security
The storage layout separates volatile download data from persistent media libraries, reducing the risk of corruption affecting user content. Hardlinks are used where supported (Btrfs/ZFS/ext4) to avoid unnecessary duplication without compromising integrity. Permissions on mounted volumes match host UID/GID (`1000:1000`) to prevent permission escalation issues when containers restart or run as non-root users inside the container runtime.

## 6. Network security
Network segmentation is effectively implemented via three distinct Docker networks: `download_net`, `app_net`, and `media_net`. qBittorrent resides solely in `download_net` connected only to Gluetun, ensuring no lateral movement between download traffic and application logic. DNS leak protection is enforced by routing all container DNS queries through Gluetun's internal interface rather than the host resolver directly.

## 7. Authentication and authorization
Authentication requirements are handled via:
- **Jellyseerr**: Requires user credentials for UI access; API keys stored securely at runtime.
- **ARR Services**: Internal communication relies on service discovery without public authentication tokens exposed in logs or environment variables by default.
- **qBittorrent WebUI**: Access restricted to internal network only, preventing unauthorized remote management attempts.
The architecture mandates that all secrets (API keys for indexers) be injected at runtime via the orchestrator's secret management system rather than hardcoded configuration files.

## 8. Secrets management
Secrets are managed exclusively through Docker-native mechanisms or environment variable injection during deployment scripts. The `secrets/` directory contains only a `.gitkeep`, ensuring no accidental commits of sensitive data to Git history per SPEC.md requirements. Placeholder values in `.env.example` do not contain real credentials; they serve solely as structural templates for the orchestrator to populate with runtime-provided secrets (e.g., ProtonVPN keys, WireGuard configs).

## 9. Dependency and supply-chain security
The architecture specifies pinned image tags where practical (`ghcr.io/devopsfactory/gluetun:latest-ubuntu2404`) rather than floating `latest` tags, reducing the risk of unexpected updates introducing vulnerabilities or breaking changes. Configuration files are stored as code in version control but exclude generated secrets and logs.

## 10. Input validation
Input validation requirements apply primarily to user-facing interfaces like Jellyseerr (request forms) and qBittorrent WebUI (if exposed). The architecture implies standard practices: sanitizing inputs before passing them to backend APIs, validating quality profile configurations via Recyclarr's declarative YAML parsing.

## 11. Missing security requirements
No critical missing requirements were identified relative to the specification. All mandatory tests (smoke, network isolation, backup integrity) are scoped in the architecture document (`tests/` directory structure). The only noted open questions concern optional port forwarding firewall rules and off-host backups; these are explicitly marked as non-critical for initial deployment approval.

## 12. Required security changes
No required security changes were identified prior to implementation. All critical controls (VPN kill-switch, network isolation, secret handling) are architecturally defined and ready for execution by the Implementer agent. The architecture document correctly identifies that `privileged: true` must never be used unless explicitly justified.

## 13. Optional security improvements
Considerations for future iterations include implementing off-host backup storage (S3/NAS) to protect against host disk failure and adding explicit firewall rule management scripts (`ufw/nftables`) for port forwarding scenarios if ProtonVPN requires them. Extending CI/CD workflows with automated vulnerability scanning of base images before deployment could further enhance supply-chain security without impacting current functionality.

## 14. Final security details
The architecture satisfies all acceptance criteria related to security: no secrets in Git, proper network isolation, least-privilege containers, and robust backup strategies defined. The design supports reproducible deployments on Ubuntu hosts with minimal host-level modifications required. All agents (Architect, Implementer, Tester) have clear responsibilities that prevent overlap or conflicting actions during the deployment lifecycle.

**FINAL_STATUS: APPROVED**