#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-repository-env.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config/profiles" "$WORK/allowed/project" "$WORK/bin"
printf '%s\n' "$WORK/allowed" > "$WORK/config/allowed-roots"
: > "$WORK/config/config"
export PODMAN_LOG="$WORK/podman.log" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$PODMAN_LOG"
exit 0
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
repo_git() { git -C "$WORK/allowed/project" "$@"; }
repo_git init -q
repo_git config user.name 'Test Developer'
repo_git config user.email dev@example.test
repo_git remote add origin 'https://alice:neverlog@github.com/team/repo.git?token=neverlog'
# Any host-side Git access during startup is a regression.
cat > "$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
echo 'Runner must not inspect host Git configuration' >&2
exit 99
EOF
chmod +x "$WORK/bin/git"
run() { : > "$PODMAN_LOG"; "$ROOT/pi-sandbox-run" --config "$WORK/config/config" --workspace "$WORK/allowed/project" "$@" > "$WORK/out" 2>&1; }
run --verbose
! grep -E '^(GH_|GITHUB_|GITLAB_|GLAB_|GIT_AUTHOR_|GIT_COMMITTER_|GIT_REMOTE_)' "$PODMAN_LOG"
! grep -E 'neverlog|Runner must not inspect' "$WORK/out" "$PODMAN_LOG"
printf '%s\n' 'ENV=GH_HOST=manual.example.test' 'ENV_SECRET=GITLAB_TOKEN=manual-token' > "$WORK/config/profiles/demo.profile"
export GH_REPO=manual/project
run demo --env GH_REPO
grep -Fx 'GH_HOST=manual.example.test' "$PODMAN_LOG" > /dev/null
grep -Fx 'manual-token,type=env,target=GITLAB_TOKEN' "$PODMAN_LOG" > /dev/null
grep -Fx 'GH_REPO' "$PODMAN_LOG" > /dev/null
run --dry-run
[[ ! -s "$PODMAN_LOG" ]]
! grep -E 'GH_HOST|GITLAB_HOST|Runner must not inspect' "$WORK/out"
echo 'User-managed repository authentication tests passed.'
