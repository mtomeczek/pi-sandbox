#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-repository-env.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config/profiles" "$WORK/allowed/project" "$WORK/bin"
printf '%s\n' "$WORK/allowed" > "$WORK/config/allowed-roots"
: > "$WORK/config/config"
export PODMAN_LOG="$WORK/podman.log" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$WORK"
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$PODMAN_LOG"
exit 0
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
run() { : > "$PODMAN_LOG"; "$ROOT/pi-sandbox-run" --config "$WORK/config/config" --workspace "$WORK/allowed/project" "$@" > "$WORK/out"; }
repo_git() { git -C "$WORK/allowed/project" "$@"; }
run
! grep -q '^GH_HOST=' "$PODMAN_LOG"
repo_git init -q
repo_git config user.name 'Test Developer'
repo_git config user.email dev@example.test
run
! grep -q '^GH_HOST=' "$PODMAN_LOG"
grep -Fx 'GIT_AUTHOR_EMAIL=dev@example.test' "$PODMAN_LOG" > /dev/null
repo_git remote add origin 'https://alice:neverlog@github.com/team/repo.git?token=neverlog'
run --verbose
for expected in 'GH_HOST=github.com' 'GH_REPO=github.com/team/repo' 'GITLAB_HOST=github.com' 'GIT_REMOTE_USER=alice' 'GIT_AUTHOR_NAME=Test Developer' 'GIT_COMMITTER_EMAIL=dev@example.test'; do
    grep -Fx -- "$expected" "$PODMAN_LOG" > /dev/null
done
! grep -F 'neverlog' "$PODMAN_LOG" "$WORK/out"
repo_git remote set-url origin 'git@gitlab.example.test:team/subgroup/repo.git'
run
for expected in 'GITLAB_HOST=gitlab.example.test' 'GITLAB_API_HOST=gitlab.example.test' 'GITLAB_REPO=team/subgroup/repo' 'GLAB_API_PROTOCOL=https' 'GIT_REMOTE_USER=git'; do
    grep -Fx -- "$expected" "$PODMAN_LOG" > /dev/null
done
repo_git remote set-url origin 'ssh://git@gitlab.example.test:2222/team/repo.git'
run
grep -Fx 'GITLAB_HOST=gitlab.example.test' "$PODMAN_LOG" > /dev/null
! grep -q '2222' "$PODMAN_LOG"
repo_git remote rename origin upstream
repo_git remote set-url upstream 'http://gitlab.example.test:8080/team/repo.git'
run
grep -Fx 'GITLAB_HOST=gitlab.example.test:8080' "$PODMAN_LOG" > /dev/null
grep -Fx 'GLAB_API_PROTOCOL=http' "$PODMAN_LOG" > /dev/null
repo_git remote set-url upstream '/tmp/local-repo.git'
run
! grep -q '^GH_HOST=' "$PODMAN_LOG"
repo_git remote set-url upstream 'https://github.com/team/repo.git'
printf '%s\n' 'ENV=GH_HOST=override.example.test' > "$WORK/config/profiles/demo.profile"
run demo
[[ "$(grep '^GH_HOST=' "$PODMAN_LOG" | tail -n 1)" == 'GH_HOST=override.example.test' ]]
run --dry-run
[[ ! -s "$PODMAN_LOG" ]]
! grep -q 'neverlog' "$WORK/out"
echo 'Repository environment tests passed.'
