#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-host-env.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config" "$WORK/allowed/project" "$WORK/bin"
printf '%s\n' "$WORK/allowed" > "$WORK/config/allowed-roots"
: > "$WORK/config/config"
export PODMAN_LOG="$WORK/podman.log"
export HOST_ENV_TEST='private value=with-hyphens'
export HOST_ENV_EMPTY=''
unset HOST_ENV_UNSET || true
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PODMAN_LOG"
if [[ "$1" == run ]]; then
    [[ "$HOST_ENV_TEST" == 'private value=with-hyphens' ]]
    [[ "${HOST_ENV_EMPTY+x}" == x && -z "$HOST_ENV_EMPTY" ]]
    [[ -z "${HOST_ENV_UNSET+x}" ]]
fi
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
run() { "$ROOT/pi-sandbox-run" --config "$WORK/config/config" --workspace "$WORK/allowed/project" "$@"; }
run --env HOST_ENV_TEST --env HOST_ENV_EMPTY --env HOST_ENV_UNSET --verbose > "$WORK/out"
grep -F -- '--env HOST_ENV_TEST --env HOST_ENV_EMPTY --env HOST_ENV_UNSET' "$PODMAN_LOG" > /dev/null
! grep -F -- "$HOST_ENV_TEST" "$PODMAN_LOG" "$WORK/out"
: > "$PODMAN_LOG"
run --env HOST_ENV_TEST --dry-run > "$WORK/out"
grep -F -- '--env HOST_ENV_TEST' "$WORK/out" > /dev/null
[[ ! -s "$PODMAN_LOG" ]]
for name in 'BAD-NAME' 'NAME=value' ''; do
    if run --env "$name" --dry-run > /dev/null 2>&1; then echo 'Invalid env name accepted' >&2; exit 1; fi
done
if run --env > /dev/null 2>&1; then echo 'Missing env argument accepted' >&2; exit 1; fi
echo 'Host environment tests passed.'
