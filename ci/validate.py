#!/usr/bin/env python3
"""
Deterministic checks for the Compose files of this repository.

GENERATED from the agent platform (orchestrator/validators.py) so that CI
and the local agents enforce exactly the same rules. Do not edit by hand:
regenerate it from the platform instead.

Usage: python3 ci/validate.py [project_dir]
Exit code 1 when at least one rule fails.
"""

from pathlib import Path
import re
import sys
from typing import Any

import yaml


def load_yaml_file(
    path: Path,
) -> Any:
    """
    Load and parse a YAML file.

    This validator contains no project-specific knowledge.
    """

    try:
        content = path.read_text(
            encoding="utf-8"
        )
    except OSError as exc:
        raise RuntimeError(
            f"unable to read YAML file {path}: {exc}"
        ) from exc

    try:
        return yaml.safe_load(content)
    except yaml.YAMLError as exc:
        raise RuntimeError(
            f"invalid YAML in {path}: {exc}"
        ) from exc



# Default listening ports of well-known images, keyed by the last
# component of the image repository. Small local models do not reliably
# know these, so healthchecks are checked deterministically.
KNOWN_IMAGE_PORTS: dict[str, set[int]] = {
    "sonarr": {8989},
    "radarr": {7878},
    "lidarr": {8686},
    "readarr": {8787},
    "prowlarr": {9696},
    "bazarr": {6767},
    "jellyfin": {8096},
    "jellyseerr": {5055},
    "overseerr": {5055},
    "qbittorrent": {8080},
    "transmission": {9091},
    "deluge": {8112},
    "sabnzbd": {8080},
    "nzbget": {6789},
    "plex": {32400},
    "tautulli": {8181},
    "flaresolverr": {8191},
}

# Environment variables through which these images change their port.
PORT_OVERRIDE_VARIABLES = ("WEBUI_PORT", "PORT")

_LOCAL_URL_RE = re.compile(
    r"(?P<scheme>https?)://(?:localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)"
    r"(?::(?P<port>\d+))?",
)
_VARIABLE_RE = re.compile(r"\$\{[^}]*\}")


def _image_name(image: str) -> str:
    """lscr.io/linuxserver/bazarr:${TAG:-latest} -> bazarr"""
    image = _VARIABLE_RE.sub("", image).split("@", 1)[0]
    last = image.rsplit("/", 1)[-1]
    return last.split(":", 1)[0].strip().lower()


def _environment(service: dict) -> dict[str, str]:
    environment = service.get("environment") or {}

    if isinstance(environment, dict):
        return {str(k): str(v) for k, v in environment.items()}

    result = {}
    for item in environment:
        key, _, value = str(item).partition("=")
        result[key.strip()] = value.strip()
    return result


def _allowed_ports(name: str, service: dict) -> set[int]:
    allowed = set(KNOWN_IMAGE_PORTS[name])

    for key, value in _environment(service).items():
        if key not in PORT_OVERRIDE_VARIABLES:
            continue
        # Accept literal values and ${VAR:-default} defaults.
        match = re.search(r"(\d+)\}?\s*$", value)
        if match:
            allowed.add(int(match.group(1)))

    return allowed


def validate_healthcheck_ports(
    project_path: str,
) -> list[str]:
    """
    Check that local healthcheck URLs of well-known images target the
    port the image actually listens on.
    """
    errors: list[str] = []

    for compose_path in sorted(Path(project_path).glob("compose*.y*ml")):
        try:
            data = load_yaml_file(compose_path)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        services = (data or {}).get("services") or {}

        for service_name, service in services.items():
            if not isinstance(service, dict):
                continue

            name = _image_name(str(service.get("image") or ""))

            if name not in KNOWN_IMAGE_PORTS:
                continue

            healthcheck = service.get("healthcheck") or {}
            test = healthcheck.get("test")

            if not test:
                continue

            command = test if isinstance(test, str) else " ".join(
                str(part) for part in test
            )
            allowed = _allowed_ports(name, service)

            for match in _LOCAL_URL_RE.finditer(command):
                port = match.group("port")
                port = int(port) if port else (
                    443 if match.group("scheme") == "https" else 80
                )

                if port in allowed:
                    continue

                expected = ", ".join(str(p) for p in sorted(allowed))
                errors.append(
                    f"{compose_path.name}: service '{service_name}' "
                    f"(image {name}) healthcheck targets local port {port}, "
                    f"but {name} listens on {expected}. Use "
                    f"http://localhost:{min(KNOWN_IMAGE_PORTS[name] & allowed or allowed)} "
                    "in the healthcheck (or set WEBUI_PORT/PORT if the "
                    "image supports a custom port)."
                )

    return errors


_DEFAULT_VARIABLE_RE = re.compile(
    r"\$\{[A-Za-z_][A-Za-z0-9_]*(?::?[-?](?P<default>[^}]*))?\}"
)
_TAG_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")


def _resolve_defaults(value: str) -> str:
    """Replace ${VAR:-default} with its default (empty when none)."""
    return _DEFAULT_VARIABLE_RE.sub(
        lambda match: match.group("default") or "", value
    )


def image_reference_error(image: str) -> str | None:
    """Return why an image reference is invalid, or None."""
    resolved = _resolve_defaults(image).strip()

    if not resolved:
        return None  # fully driven by variables: cannot judge

    name, _, digest = resolved.partition("@")
    last = name.rsplit("/", 1)[-1]

    if last.count(":") > 1:
        message = (
            f"image '{image}' resolves to '{resolved}', which has more than "
            "one tag; a reference is name[:tag][@digest]"
        )
        head, _, trailing = image.rpartition(":")
        if head and "}" not in trailing and "/" not in trailing:
            message += (
                f". Replace the line with exactly: image: {head} "
                f"(remove the extra ':{trailing}')"
            )
        return message

    if ":" in last:
        tag = last.split(":", 1)[1]
        if not _TAG_RE.match(tag):
            return (
                f"image '{image}' resolves to '{resolved}', whose tag "
                f"'{tag}' is invalid"
            )

    if name != name.strip() or " " in name:
        return f"image '{image}' contains spaces"

    return None


def validate_image_references(
    project_path: str,
) -> list[str]:
    errors: list[str] = []

    for compose_path in sorted(Path(project_path).glob("compose*.y*ml")):
        try:
            data = load_yaml_file(compose_path)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        services = (data or {}).get("services") or {}

        for service_name, service in services.items():
            if not isinstance(service, dict) or not service.get("image"):
                continue

            error = image_reference_error(str(service["image"]))

            if error:
                errors.append(
                    f"{compose_path.name}: service '{service_name}': {error}."
                )

    return errors


_BARE_VARIABLE_RE = re.compile(
    r"\$\{(?P<name>[A-Za-z_][A-Za-z0-9_]*)\}|\$(?P<plain>[A-Za-z_][A-Za-z0-9_]*)"
)


def split_volume(volume: str) -> list[str]:
    """Split a short-syntax volume on ':' outside ${...} expressions."""
    parts, current, depth = [], "", 0
    for character in volume:
        if character == "{" and current.endswith("$"):
            depth += 1
        elif character == "}" and depth:
            depth -= 1
        if character == ":" and not depth:
            parts.append(current)
            current = ""
        else:
            current += character
    parts.append(current)
    return parts


def _volume_source(volume: Any) -> str | None:
    if isinstance(volume, dict):
        if volume.get("type", "bind") != "bind":
            return None
        return str(volume.get("source") or "")
    parts = split_volume(str(volume))
    if len(parts) == 1:
        return None  # anonymous volume
    return parts[0]


def validate_bind_mount_defaults(
    project_path: str,
) -> list[str]:
    """
    Reject bind mounts whose host path uses a variable without a default:
    an unset variable silently turns '${ROOT}/media' into '/media' on the
    host (for example local disk instead of a NAS mount).
    """
    errors: list[str] = []

    for compose_path in sorted(Path(project_path).glob("compose*.y*ml")):
        try:
            data = load_yaml_file(compose_path)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        services = (data or {}).get("services") or {}

        for service_name, service in services.items():
            if not isinstance(service, dict):
                continue

            for volume in service.get("volumes") or []:
                source = _volume_source(volume)

                if not source:
                    continue

                for match in _BARE_VARIABLE_RE.finditer(source):
                    name = match.group("name") or match.group("plain")
                    errors.append(
                        f"{compose_path.name}: service '{service_name}': "
                        f"bind mount source '{source}' uses ${{{name}}} "
                        "without a default; if the variable is unset the "
                        "host path changes silently. Use "
                        f"${{{name}:-<default path>}} instead."
                    )

    return errors


def _is_linuxserver_image(image: str) -> bool:
    repository = _VARIABLE_RE.sub("", image).split("@", 1)[0].lower()
    parts = repository.split("/")
    return len(parts) >= 2 and parts[-2] == "linuxserver"


def _volume_target(volume: Any) -> str | None:
    if isinstance(volume, dict):
        return str(volume.get("target") or "") or None
    parts = split_volume(str(volume))
    if len(parts) == 1:
        return parts[0]
    return parts[1]


def validate_linuxserver_config_volumes(
    project_path: str,
) -> list[str]:
    """
    linuxserver.io images keep all application state in /config. A mount
    on /config/<app> leaves /config itself inside the container, so the
    configuration is lost when the container is recreated.
    """
    errors: list[str] = []

    # Only the production stack: dev/test stacks are ephemeral on purpose.
    for compose_path in [Path(project_path) / "compose.yaml"]:
        if not compose_path.exists():
            continue

        try:
            data = load_yaml_file(compose_path)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        services = (data or {}).get("services") or {}

        for service_name, service in services.items():
            if not isinstance(service, dict):
                continue

            image = str(service.get("image") or "")

            if not _is_linuxserver_image(image):
                continue

            volumes = service.get("volumes") or []
            targets = [
                (_volume_target(volume) or "").rstrip("/") or "/"
                for volume in volumes
            ]

            if "/config" in targets:
                continue

            nested = [
                (volume, target)
                for volume, target in zip(volumes, targets)
                if target.startswith("/config/")
            ]

            if nested:
                volume, target = nested[0]
                fix = ""
                if isinstance(volume, str):
                    fixed = volume.replace(f":{target}", ":/config", 1)
                    fix = f" Replace '- {volume}' with '- {fixed}'."
                errors.append(
                    f"{compose_path.name}: service '{service_name}' "
                    f"(linuxserver image) mounts its configuration on "
                    f"'{target}', but linuxserver images store their state "
                    f"in /config itself; the configuration would be lost on "
                    f"container recreation.{fix}"
                )
            else:
                errors.append(
                    f"{compose_path.name}: service '{service_name}' "
                    "(linuxserver image) has no volume mounted on /config; "
                    "its configuration would be lost on container "
                    "recreation. Add a volume such as "
                    "'- ${HOST_CONFIG_ROOT:-<config dir>}/"
                    f"{service_name}:/config'."
                )

    return errors


CHECKS = (
    validate_image_references,
    validate_healthcheck_ports,
    validate_bind_mount_defaults,
    validate_linuxserver_config_volumes,
)


def main() -> int:
    project = sys.argv[1] if len(sys.argv) > 1 else "."
    errors = [error for check in CHECKS for error in check(project)]

    for error in errors:
        print(f"::error::{error}")

    print(f"{len(errors)} error(s) in {len(CHECKS)} checks.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
