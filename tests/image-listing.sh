#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/test-image-listing.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

FAKE_BIN="$WORK_DIR/bin"
PODMAN_LOG="$WORK_DIR/podman.log"
mkdir -p "$FAKE_BIN" "$WORK_DIR/config"
export PODMAN_LOG
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$PODMAN_LOG"
printf '\n' >>"$PODMAN_LOG"
case "$1 $2" in
  'info ') exit 0 ;;
  'image exists') exit 1 ;;
  'image ls')
    printf 'localhost/pi-sandbox-golang\tpi-sandbox\tcba83e58e23c\t6 days ago\t729 MB\n'
    printf 'localhost/pi-sandbox-golang\tlatest\tcba83e58e23c\t6 days ago\t729 MB\n'
    printf 'localhost/other\tpi-sandbox\tdeadbeef\t1 day ago\t10 MB\n'
    exit 0 ;;
esac
EOF
chmod +x "$FAKE_BIN/podman"
export PATH="$FAKE_BIN:$PATH"

IMAGE='localhost/pi-sandbox-golang:latest'
"$ROOT_DIR/pi-sandbox-create" --config "$WORK_DIR/config/config" --image "$IMAGE" --build >/dev/null
grep -F -- "tag $IMAGE localhost/pi-sandbox-golang:pi-sandbox" "$PODMAN_LOG" >/dev/null

for command in "$ROOT_DIR/pi-sandbox-run" "$ROOT_DIR/pi-sandbox-create"; do
	output="$("$command" --list-images)"
	grep -F -- 'localhost/pi-sandbox-golang' <<<"$output" >/dev/null
	grep -F -- 'pi-sandbox' <<<"$output" >/dev/null
	[[ "$output" != *'latest'* ]]
	grep -F -- 'localhost/other' <<<"$output" >/dev/null
done

printf 'Image-listing tests passed.\n'
