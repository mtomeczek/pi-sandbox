#!/bin/sh
# Run the official managed installer against a locked release snapshot.
set -eu
export PATH="/opt/pi/node/bin:$PATH"
: "${PI_VERSION:?PI_VERSION is required}"
: "${PI_SANDBOX_AGENT_DIR:?PI_SANDBOX_AGENT_DIR is required}"
api=https://pi.dev/api/installer/releases
work=$(mktemp -d)
server_pid=
cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ "$PI_VERSION" = latest ]; then
    curl -fsSLo "$work/latest" "$api/latest"
    version=$(jq -er '.version' "$work/latest")
else
    npm view "@earendil-works/pi-coding-agent@${PI_VERSION}" version --json > "$work/version.json"
    version=$(jq -er 'if type == "array" then last else . end | select(type == "string")' "$work/version.json")
fi
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
# Only published managed-release manifests are accepted; never fall back to latest.
for artifact in package.json package-lock.json; do
    curl -fsSLo "$work/$artifact" "$api/$version/$artifact"
done
curl -fsSLo "$work/install.sh" https://pi.dev/install.sh
node /usr/local/lib/pi-sandbox/installer-server.cjs "$work" "$version" &
server_pid=$!
attempt=0
while [ ! -s "$work/port" ]; do
    kill -0 "$server_pid"
    attempt=$((attempt + 1))
    [ "$attempt" -lt 100 ] || { echo "Pi installer snapshot server did not start" >&2; exit 1; }
    sleep 0.1
done
port=$(cat "$work/port")
# The official installer has no version flag. A temporary loopback-only API
# serves its expected /latest endpoint and the selected upstream lock files.
PI_CODING_AGENT_DIR="$PI_SANDBOX_AGENT_DIR" \
    PI_MANAGED_INSTALL_ROOT="$PI_SANDBOX_AGENT_DIR/install" \
    PI_INSTALLER_API_BASE="http://127.0.0.1:$port" PI_LEGACY_INSTALL=0 \
    sh "$work/install.sh" </dev/null
test "$(cat "$PI_SANDBOX_AGENT_DIR/install/current-version")" = "$version"
# Keep the public launcher independent of HOME, the state volume, and project Node.
rm -f "$HOME/.local/bin/pi"
ln -s /usr/local/lib/pi-sandbox/pi.sh "$HOME/.local/bin/pi"
test "$(pi --version)" = "$version"
npm cache clean --force
