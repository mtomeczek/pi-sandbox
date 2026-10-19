#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-profile-secrets.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config/profiles" "$WORK/allowed/project" "$WORK/bin"
printf '%s\n' "$WORK/allowed" > "$WORK/config/allowed-roots"
: > "$WORK/config/config"
export PODMAN_LOG="$WORK/podman.log"
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PODMAN_LOG"
exit 0
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
run() { "$ROOT/pi-sandbox-run" demo --config "$WORK/config/config" --workspace "$WORK/allowed/project" "$@"; }
run --dry-run > "$WORK/out"
! grep -q -- '--secret' "$WORK/out"
printf '%s\n' 'ENV_SECRET=GITLAB_TOKEN=gitlab-token' 'ENV_SECRET=GITHUB_TOKEN=github-token' > "$WORK/config/profiles/demo.profile"
run --dry-run > "$WORK/out"
grep -F -- 'gitlab-token\,type=env\,target=GITLAB_TOKEN' "$WORK/out"
grep -F -- 'github-token\,type=env\,target=GITHUB_TOKEN' "$WORK/out"
run > /dev/null
grep -F -- '--secret gitlab-token,type=env,target=GITLAB_TOKEN' "$PODMAN_LOG"
printf '%s\n' 'ENV_SECRET=GITHUB_TOKEN=bad,type=mount' > "$WORK/config/profiles/demo.profile"
if run --dry-run > /dev/null 2>&1; then echo 'Invalid secret accepted' >&2; exit 1; fi
printf '%s\n' 'ENV=APP_MODE=dev-test' 'ENV=URL=https://example.test/?a=b=c' 'ENV=EMPTY=' 'ENV_SECRET=API_TOKEN=my-api-secret' > "$WORK/config/profiles/demo.profile"
run > /dev/null
grep -F -- '--env APP_MODE=dev-test' "$PODMAN_LOG"
grep -F -- '--env URL=https://example.test/?a=b=c' "$PODMAN_LOG"
grep -F -- '--env EMPTY=' "$PODMAN_LOG"
grep -F -- '--secret my-api-secret,type=env,target=API_TOKEN' "$PODMAN_LOG"
for entry in 'ENV=APP_MODE-dev' 'ENV_SECRET=API_TOKEN-my-secret' 'ENV=BAD-NAME=value' 'ENV_SECRET=API_TOKEN=' 'ENV_SECRET=API_TOKEN=bad,type=mount'; do
    printf '%s\n' "$entry" > "$WORK/config/profiles/demo.profile"
    if run --dry-run > /dev/null 2>&1; then echo 'Invalid ENV directive accepted' >&2; exit 1; fi
done
echo 'Profile secret and environment tests passed.'
