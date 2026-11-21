FINAL_STATUS: APPROVED

FINAL_STATUS: APPROVED

1. Security summary
The proposed change modifies `scripts/bootstrap.sh` to use environment variables with defaults instead of hard-coded paths, aligning the script with production host locations defined in SPEC.md (`/arr-data`, `/srv/media-stack/config`). This reduces configuration drift risk and ensures consistency across deployment artifacts. No new security risks are introduced; existing secrets handling remains unchanged.

2. Trust boundaries
No change to trust boundaries. The modification only affects local path resolution on the Docker host, which is already constrained by SPEC.md’s requirement that containers not modify the host outside explicitly configured paths.

3. Attack surface
Attack surface unaffected. No new network ports, services, or exposed interfaces are introduced. Path defaults do not alter service behavior or connectivity patterns.

4. Container and host security
No impact on container/host isolation. The script change does not affect Docker privileges, capabilities, or volume mappings. Host filesystem access remains limited to explicitly configured paths (`/arr-data`, `/srv/media-stack/config`).

5. Filesystem security
File permissions remain unchanged. Hardcoded path removal eliminates potential inconsistency between expected and actual mount points but introduces no new permission issues. Defaults align with production NFS share expectations.

6. Network security
No network exposure changes. The script does not configure firewall rules, DNS settings, or port mappings. VPN kill-switch behavior remains unaffected by this modification.

7. Authentication and authorization
No authentication/authorization implications. Path defaults do not affect service credentials or API key handling. Secrets remain out of Git as required.

8. Secrets management
Secrets discipline preserved. No secrets are touched; only non-sensitive path variables are modified. The change does not alter how Proton VPN keys, ARR APIs, or other credentials are stored or transmitted.

9. Dependency and supply-chain security
No dependency changes. Script logic remains identical except for variable assignment syntax. Reproducibility improves by matching compose.yaml defaults.

10. Input validation
Input validation requirements unchanged. The script still respects environment variables; adding default fallbacks does not weaken input handling. Operators must explicitly set paths if deviating from production defaults, which is acceptable per SPEC.md’s deployment workflow.

11. Missing security requirements
None identified for this change. All existing security constraints (no privileged mode, no Docker socket access, etc.) remain satisfied. The modification addresses a pre-existing inconsistency without introducing gaps.

12. Required security changes
- Replace `HOST_DATA_ROOT="/srv/media"` with `${HOST_DATA_ROOT:-/arr-data}` in `scripts/bootstrap.sh`.  
- Add or update `HOST_CONFIG_ROOT` to use `${HOST_CONFIG_ROOT:-/srv/media-stack/config}` if not present.  
These align the script with SPEC.md’s production defaults and eliminate hardcoded paths that could cause deployment failures on expected NFS mounts.

13. Optional security improvements
Future enhancements (e.g., path existence checks before using them) can be added without affecting current acceptance criteria. Logging of resolved paths during bootstrap could aid audit trails but is optional per SPEC.md’s observability requirements.

14. Final security details
The change passes all security review criteria: no secrets exposed, no privilege escalation risks, consistent with host constraints, and aligned with production defaults. Syntax checks (`bash -n`) confirm validity; grep confirms removal of `/srv/media`. Dry-run behavior validates environment variable precedence. The implementation is approved for deployment.