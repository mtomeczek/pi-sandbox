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

mkdir -p -- "${CONFIG_HOME}/pi-sandbox" "$ALLOWED_PROJECT" "$ALLOWED_PROJECT/shared" "$ALLOWED_PROJECT/extension" "$UNDECLARED_PROJECT" "$FAKE_BIN"
printf '%s\n' "$ALLOWED_ROOT" >"${CONFIG_HOME}/pi-sandbox/allowed-roots"
PODMAN_LOG="${WORK_DIR}/podman.log"
export PODMAN_LOG
cat >"${FAKE_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$PODMAN_LOG"
printf '\n' >>"$PODMAN_LOG"
exit 0
EOF
chmod +x -- "${FAKE_BIN}/podman"

export PATH="${FAKE_BIN}:${PATH}"

"${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --info --dry-run >/dev/null
"${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --init --name initialized >/dev/null
grep -Fx 'NAME=initialized' "${ALLOWED_PROJECT}/.pisandboxrc" >/dev/null
if "${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --init >/dev/null 2>&1; then
	printf 'Existing project config was overwritten.\n' >&2
	exit 1
fi

if "${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$UNDECLARED_PROJECT" --info --dry-run >/dev/null 2>&1; then
	printf 'Undeclared directory was accepted as a mount source.\n' >&2
	exit 1
fi

cat >"${ALLOWED_PROJECT}/.pisandboxrc" <<'EOF'
NAME=from-rc
PORT=3000:3000
PORT=9229:9229/tcp
MOUNT=./shared:/src/shared:ro
PI_EXTENSION=./extension
EOF
"${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --name from-cli --port 4000:4000 >/dev/null

grep -F -- '--publish 3000:3000/tcp' "$PODMAN_LOG" >/dev/null
grep -F -- '--publish 9229:9229/tcp' "$PODMAN_LOG" >/dev/null
grep -F -- '--publish 4000:4000/tcp' "$PODMAN_LOG" >/dev/null
grep -F -- 'pi-agent-from-cli' <("${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --name from-cli --info --dry-run) >/dev/null

echo 'PORT=70000:3000' >"${ALLOWED_PROJECT}/.pisandboxrc"
if "${ROOT_DIR}/pi-sandbox-run" --config "${CONFIG_HOME}/pi-sandbox/config" --workspace "$ALLOWED_PROJECT" --dry-run >/dev/null 2>&1; then
	printf 'Invalid project port was accepted.\n' >&2
	exit 1
fi

printf 'Allowed-root tests passed.\n'
