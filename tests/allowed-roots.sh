#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/test-allowed-roots.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

CONFIG_HOME="${WORK_DIR}/config"
ALLOWED_ROOT="${WORK_DIR}/allowed-root"
ALLOWED_PROJECT="${ALLOWED_ROOT}/project"
UNDECLARED_PROJECT="${WORK_DIR}/undeclared/project"
FAKE_BIN="${WORK_DIR}/bin"

mkdir -p -- "${CONFIG_HOME}/pi-sandbox" "$ALLOWED_PROJECT" "$UNDECLARED_PROJECT" "$FAKE_BIN"
printf '%s\n' "$ALLOWED_ROOT" >"${CONFIG_HOME}/pi-sandbox/allowed-roots"
printf '#!/usr/bin/env bash\nexit 0\n' >"${FAKE_BIN}/podman"
chmod +x -- "${FAKE_BIN}/podman"

export PATH="${FAKE_BIN}:${PATH}"

"${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --info --dry-run >/dev/null

if "${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$UNDECLARED_PROJECT" --info --dry-run >/dev/null 2>&1; then
	printf 'Undeclared directory was accepted as a mount source.\n' >&2
	exit 1
fi

printf 'Allowed-root tests passed.\n'
