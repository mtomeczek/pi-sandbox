#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_FILE="${ROOT_DIR}/docs/release-policy.md"
BASH_CREATOR="${ROOT_DIR}/pi-sandbox-create"
POWERSHELL_CREATOR="${ROOT_DIR}/scripts/windows/pi-sandbox-create.ps1"

minimum_version="$(awk -F'`' '/^Minimum supported Podman version:/{print $2; exit}' "$POLICY_FILE")"
pi_version="$(awk -F'"' '/^PI_VERSION=/{print $2; exit}' "$BASH_CREATOR")"
base_image="$(awk -F'"' '/^BASE_IMAGE=/{print $2; exit}' "$BASH_CREATOR")"

[[ "$minimum_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	printf 'Invalid minimum Podman version in %s: %s\n' "$POLICY_FILE" "$minimum_version" >&2
	exit 1
}
[[ -n "$pi_version" && -n "$base_image" ]] || {
	printf 'Could not read Bash image defaults.\n' >&2
	exit 1
}
grep -Fq "Default Pi version: \`${pi_version}\`" "$POLICY_FILE"
grep -Fq "Default base image: \`${base_image}\`" "$POLICY_FILE"
grep -Fq "\$PiVersion = '${pi_version}'" "$POWERSHELL_CREATOR"
grep -Fq "\$BaseImage = '${base_image}'" "$POWERSHELL_CREATOR"

version_at_least() {
	local actual="$1" required="$2" actual_major actual_minor actual_patch required_major required_minor required_patch

	IFS=. read -r actual_major actual_minor actual_patch <<<"${actual%%-*}"
	IFS=. read -r required_major required_minor required_patch <<<"$required"
	[[ "$actual_major" =~ ^[0-9]+$ && "$actual_minor" =~ ^[0-9]+$ && "$actual_patch" =~ ^[0-9]+$ ]] || return 1
	if ((actual_major != required_major)); then
		((actual_major > required_major))
		return
	fi
	if ((actual_minor != required_minor)); then
		((actual_minor > required_minor))
		return
	fi
	((actual_patch >= required_patch))
}

podman_version="${PODMAN_VERSION:-}"
if [[ -z "$podman_version" ]]; then
	command -v podman >/dev/null 2>&1 || {
		printf 'Set PODMAN_VERSION to test compatibility without Podman installed.\n' >&2
		exit 1
	}
	podman_version="$(podman --version | awk '{print $3}')"
fi

version_at_least "$podman_version" "$minimum_version" || {
	printf 'Podman %s is below the supported minimum %s.\n' "$podman_version" "$minimum_version" >&2
	exit 1
}
printf 'Release policy checks passed (Podman %s; minimum %s).\n' "$podman_version" "$minimum_version"
