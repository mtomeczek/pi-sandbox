#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/test-standard-image.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat > "$WORK/bin/podman" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$WORK/bin/podman"
export PATH="$WORK/bin:$PATH"
export XDG_CONFIG_HOME="$WORK/config"
"$ROOT/pi-sandbox-create" --regenerate-containerfile > /dev/null
"$ROOT/pi-sandbox-create" --create standard-test --tool go@1.24.0 > /dev/null
for suffix in '' '.standard-test'; do
    file="$XDG_CONFIG_HOME/pi-sandbox/dockerfiles/Containerfile.pi-sandbox$suffix"
    grep -F -- 'git gh glab curl' "$file" > /dev/null
    grep -F -- 'bookworm-backports main' "$file" > /dev/null
    grep -F -- '&& gh --version && glab --version' "$file" > /dev/null
done
echo 'Standard image generation tests passed.'
