FINAL_STATUS: APPROVED

FINAL_STATUS: APPROVED

## 1. Review summary
The proposed change to `scripts/bootstrap.sh` is minimal, targeted, and fully aligned with SPEC.md requirements regarding host path consistency (`/arr-data` for data, `/srv/media-stack/config` for config). The architecture modification removes a hardcoded production-incompatible value in favor of environment-variable-driven defaults that match the compose stack. No new components or services are introduced; only variable assignment logic is corrected to prevent future drift between scripts and Docker Compose configurations.

## 2. Requirements coverage
- **Storage layout**: SPEC.md explicitly defines `/arr-data` as the production data root and `/srv/media-stack/config` for configuration. The change enforces these defaults via `${VAR:-default}` syntax, ensuring `bootstrap.sh` no longer contradicts `.env.example`, `compose.yaml`, or host constraints.
- **Reproducibility**: Defaults now match those in Docker Compose files, enabling a clean checkout to recreate the stack without manual path adjustments.
- **Secrets discipline**: No secrets are touched; only non-sensitive paths are modified.

## 3. Architecture issues
None detected. The change is purely cosmetic (path defaults) and does not alter service topology, networking, or dependencies.

## 4. Security issues
No security concerns: the modification removes a hardcoded path that could have been inconsistent with production expectations but poses no direct risk. No secrets are exposed or altered.

## 5. Testing issues
The change-plan includes clear tests (syntax check, grep for removed hardcode, dry-run behavior). These can be executed by the Tester agent post-implementation without modifying existing test infrastructure. All acceptance criteria are verifiable via standard shell commands and do not require runtime artifacts beyond the modified script.

## 6. Deployment issues
None anticipated. The script remains idempotent; defaults are applied only when environment variables are unset or empty. Existing deployments using explicit `HOST_DATA_ROOT`/`HOST_CONFIG_ROOT` will continue unaffected. No host-level side effects occur outside explicitly configured paths.

## 7. Unnecessary complexity
The change reduces complexity by eliminating a hard-coded path, improving maintainability and alignment with SPEC.md. No added logic is introduced; the script’s existing flow remains intact except for two variable assignments.

## 8. Missing requirements
None identified for this specific change request. All acceptance criteria (syntax check, no `/srv/media` in script, dry-run behavior) are achievable within the scope of modifying only `scripts/bootstrap.sh`. No additional components or documentation updates are required by SPEC.md for this isolated fix.

## 9. Required changes
- Replace line 12’s hardcoded assignment with `${HOST_DATA_ROOT:-/arr-data}`.
- Add or update `HOST_CONFIG_ROOT` to use `${HOST_CONFIG_ROOT:-/srv/media-stack/config}` if not already present.
- Ensure no other lines in the file are altered, preserving all existing logic and comments outside these two assignments.

## 10. Optional improvements
None required for this change request. Future enhancements (e.g., additional validation of paths) can be addressed separately without affecting current acceptance criteria. Monitoring or logging additions fall under optional services per SPEC.md and are out of scope here.

## 11. Final review details
The architecture is approved because:
- The change directly addresses a SPEC.md inconsistency (hardcoded path vs production defaults).
- It adheres strictly to the constraint “do not modify any other file.”
- No new risks, dependencies, or ambiguities are introduced.
- All acceptance criteria can be verified without implementation artifacts beyond the modified script.

The status is APPROVED; proceed with implementing only the two-line modification in `scripts/bootstrap.sh`.