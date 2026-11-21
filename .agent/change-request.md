# Use the production host paths in scripts/bootstrap.sh

`scripts/bootstrap.sh` hard-codes `HOST_DATA_ROOT="/srv/media"` (line 12),
while the stack now keeps its data on the NAS share mounted at `/arr-data`
(see "Storage requirements" in SPEC.md, `.env.example` and the defaults in
`compose.yaml`).

Required change:

- `HOST_DATA_ROOT` and `HOST_CONFIG_ROOT` in `scripts/bootstrap.sh` must
  honour values already set in the environment, and otherwise default to
  the same values as `compose.yaml`: `/arr-data` and
  `/srv/media-stack/config`. Use the `${VAR:-default}` form.
- Do not change anything else in the script, nor any other file. In
  particular, do not change `compose.yaml`, `.env.example` or the
  workflows.

Acceptance:

- `bash -n scripts/bootstrap.sh` succeeds.
- `grep -n '/srv/media"' scripts/bootstrap.sh` finds nothing.
- `HOST_DATA_ROOT=/tmp/x ./scripts/bootstrap.sh --dry-run` uses `/tmp/x`.
