# Change summary

The change updates `scripts/bootstrap.sh` to use environment variables with defaults instead of hard-coded paths, aligning it with the production host locations defined in SPEC.md (`/arr-data` for data and `/srv/media-stack/config` for config). This ensures consistency across compose files, scripts, and documentation.

# Files to modify

- `scripts/bootstrap.sh`: Replace line 12's hardcoded `HOST_DATA_ROOT="/srv/media"` with `${HOST_DATA_ROOT:-/arr-data}`; replace the existing `HOST_CONFIG_ROOT` assignment (if present) or add it as `${HOST_CONFIG_ROOT:-/srv/media-stack/config}`. Do not modify any other lines in this file, nor touch `compose.yaml`, `.env.example`, workflows, or documentation files.

# Implementation steps

1. Open and read `scripts/bootstrap.sh`.
2. Locate line 12 (or the nearest assignment for `HOST_DATA_ROOT`) that currently reads:  
   ```bash
   HOST_DATA_ROOT="/srv/media"
   ```
3. Replace it with:  
   ```bash
   export HOST_DATA_ROOT="${HOST_DATA_ROOT:-/arr-data}"
   ```
4. Locate any existing line setting `HOST_CONFIG_ROOT` (if present). If missing, add after the previous step:  
   ```bash
   export HOST_CONFIG_ROOT="${HOST_CONFIG_ROOT:-/srv/media-stack/config}"
   ```
5. Ensure no other lines in `scripts/bootstrap.sh` are changed; preserve all logic and comments outside these two assignments.

# Tests

- Run syntax check: `bash -n scripts/bootstrap.sh`. Expect success (exit code 0).
- Verify hard-coded path removed:  
  ```bash
  grep '/srv/media"' scripts/bootstrap.sh && echo "FAIL" || echo "PASS"
  ```
  Should output `PASS` with no matches.
- Test default fallback behavior:  
  ```bash
  HOST_DATA_ROOT=/tmp/x ./scripts/bootstrap.sh --dry-run
  ```
  Confirm that the script uses `/tmp/x`. If a dry-run flag is not implemented, inspect environment variable usage in subsequent commands or logs to confirm it respects `HOST_DATA_ROOT` from env.

# Risks

- Minimal risk: only two lines changed; no functional logic altered.  
- Potential issue if downstream scripts depend on the old hardcoded value before this change propagates—mitigated by using consistent defaults matching SPEC.md and compose.yaml, which are already in production alignment.