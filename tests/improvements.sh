#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-improvements.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config/profiles" "$WORK/root/project" "$WORK/bin"
printf '%s\n' "$WORK/root" > "$WORK/config/allowed-roots"
: > "$WORK/config/config"
export PODMAN_LOG="$WORK/podman.log"
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PODMAN_LOG"
case "$1 $2" in
  'info --format') echo '{"host":{"security":{"rootless":true}}}' ;;
  'image inspect') echo '[{"Config":{"Labels":{"io.pi-sandbox.template-version":"3","io.pi-sandbox.capabilities":"gh,glab-device"}}}]' ;;
  'run '*) if [[ "${FAIL_BOOTSTRAP:-0}" == 1 && "$*" == *'pi install -l'* ]]; then exit 9; fi ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
cat > "$WORK/config/profiles/demo.profile" <<'EOF'
PROFILE=demo
BASE_IMAGE=node:24-bookworm-slim
PI_VERSION=1.0.0
TOOL=go@1.26.0
ENV_SECRET=API_TOKEN=api-token
EOF
create() { "$ROOT/pi-sandbox-create" demo --config "$WORK/config/config" "$@"; }
run() { "$ROOT/pi-sandbox-run" --config "$WORK/config/config" --workspace "$WORK/root/project" "$@"; }
create --pi-version 1.4.0 --base-image node:24-bookworm-slim --image manual:tag --tool go@1.27.3 --info > "$WORK/out"
grep -F 'Pi version:    1.4.0' "$WORK/out" > /dev/null
grep -F 'go@1.27.3' "$WORK/out" > /dev/null
! grep -F 'go@1.26.0' "$WORK/out"
grep -F 'manual:tag' "$WORK/out" > /dev/null
create --validate > /dev/null
mkdir -p "$WORK/read-only/profiles"
cp "$WORK/config/profiles/demo.profile" "$WORK/read-only/profiles/demo.profile"
"$ROOT/pi-sandbox-create" demo --config "$WORK/read-only/config" --validate > /dev/null
[[ ! -e "$WORK/read-only/config" ]]
if "$ROOT/pi-sandbox-create" --config "$WORK/config/config" --create invalid --tool python@3.13.0 --dry-run > /dev/null 2>&1; then echo 'Invalid dependency accepted' >&2; exit 1; fi
[[ ! -e "$WORK/config/profiles/invalid.profile" ]]
if "$ROOT/pi-sandbox-create" --config "$WORK/config/config" --create invalid --tool go@1.27.3 --shell-command $'echo ok\nENV=INJECTED=value' --dry-run > /dev/null 2>&1; then echo 'Multiline profile injection accepted' >&2; exit 1; fi
"$ROOT/pi-sandbox-create" --config "$WORK/config/config" --create custom --tool go@1.27.3 --image custom:test --dry-run > "$WORK/out"
grep -F -- '--tag custom:test' "$WORK/out" > /dev/null
create --update --dry-run > "$WORK/out"
grep -F 'io.pi-sandbox.profile=demo' "$WORK/out" > /dev/null
[[ ! -e "$WORK/config/dockerfiles/Containerfile.pi-sandbox.demo" ]]
create --regenerate-containerfile > /dev/null
printf '%s\n' '# old saved Containerfile' > "$WORK/config/dockerfiles/Containerfile.pi-sandbox.demo"
if create --update --dry-run > "$WORK/out" 2>&1; then echo 'Stale Containerfile accepted' >&2; exit 1; fi
grep -F -- '--regenerate-containerfile --update' "$WORK/out" > /dev/null
run demo --init --name backend > /dev/null
grep -Fx 'PROFILE=demo' "$WORK/root/project/.pisandboxrc" > /dev/null
# Leave the instance name out for the volume-name assertions below.
printf '%s\n' 'PROFILE=demo' > "$WORK/root/project/.pisandboxrc"
run --dry-run --persist-cli-auth > "$WORK/out"
grep -F 'pi-sandbox-demo:latest' "$WORK/out" > /dev/null
grep -F 'pi-agent-demo-gh-auth' "$WORK/out" > /dev/null
grep -F 'pi-agent-demo-glab-auth' "$WORK/out" > /dev/null
run --dry-run --image custom:tag > "$WORK/out"
grep -F 'custom:tag' "$WORK/out" > /dev/null
! grep -F 'pi-sandbox-demo:latest' "$WORK/out"
! grep -F 'gh-auth' "$WORK/out"
run --reset-cli-auth --dry-run > "$WORK/out"
grep -F 'podman volume rm pi-agent-demo-gh-auth' "$WORK/out" > /dev/null
run --reset-cli-auth --yes > /dev/null
grep -F 'volume rm pi-agent-demo-glab-auth' "$PODMAN_LOG" > /dev/null
: > "$PODMAN_LOG"
run --doctor --dry-run > "$WORK/out"
grep -F 'Doctor would check Podman' "$WORK/out" > /dev/null
[[ ! -s "$PODMAN_LOG" ]]
if run --doctor --reset-cli-auth --yes > /dev/null 2>&1; then echo 'Destructive doctor combination accepted' >&2; exit 1; fi
printf '%s\n' 'PROFILE=demo' 'PI_EXTENSION=npm:example' > "$WORK/root/project/.pisandboxrc"
: > "$PODMAN_LOG"
if FAIL_BOOTSTRAP=1 run > "$WORK/out" 2>&1; then echo 'Bootstrap failure ignored' >&2; exit 1; fi
[[ "$(grep -c '^run ' "$PODMAN_LOG")" == 1 ]]
! grep -F 'Starting Pi sandbox' "$WORK/out"
echo 'Creation and runtime improvement tests passed.'
