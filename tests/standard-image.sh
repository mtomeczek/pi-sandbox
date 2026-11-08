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
"$ROOT/pi-sandbox-create" --create standard-test --tool go@1.27.3 --tool caddy@2.11.9 --tool jvm@21.0.13+9 --tool playwright@1.65.0 > /dev/null
for suffix in '' '.standard-test'; do
    file="$XDG_CONFIG_HOME/pi-sandbox/dockerfiles/Containerfile.pi-sandbox$suffix"
    grep -F -- 'git curl' "$file" > /dev/null
    grep -F -- 'ARG GH_VERSION=2.103.3' "$file" > /dev/null
    grep -F -- 'ARG PI_NODE_IMAGE=node:24.22.2-bookworm-slim' "$file" > /dev/null
    grep -F -- 'install -m 0755 bin/gh /usr/local/bin/gh' "$file" > /dev/null
    grep -F -- 'ARG BASE_IMAGE=debian:bookworm-slim' "$file" > /dev/null
    grep -F -- 'FROM ${PI_NODE_IMAGE} AS pi-node' "$file" > /dev/null
    grep -F -- 'COPY --from=pi-node /usr/local/bin/node /opt/pi/node/bin/node' "$file" > /dev/null
    grep -F -- 'COPY pi-sandbox/ /usr/local/lib/pi-sandbox/' "$file" > /dev/null
    grep -F -- 'RUN /usr/local/lib/pi-sandbox/install-pi.sh' "$file" > /dev/null
    ! grep -F -- 'npm install -g --ignore-scripts "@earendil-works/pi-coding-agent' "$file"
    ! grep -F -- 'ENV PATH="/opt/pi/node/bin' "$file"
    ! grep -F -- 'exec "/usr/local/bin/node"' "$file"
    grep -F -- 'fnm use >/dev/null || true' "$file" > /dev/null
    ! grep -F -- 'fnm use --silent' "$file"
    grep -F -- 'ARG GLAB_VERSION=1.128.0' "$file" > /dev/null
    grep -F -- 'sha256sum -c selected-checksum.txt' "$file" > /dev/null
    grep -F -- 'install -m 0755 bin/glab /usr/local/bin/glab' "$file" > /dev/null
    grep -F -- "glab auth login --help | grep -q -- '--device'" "$file" > /dev/null
    ! grep -q 'bookworm-backports' "$file"
    if [[ -n "$suffix" ]]; then
        grep -F -- '/tmp/go-releases.json' "$file" > /dev/null
        grep -F -- 'checker=sha512sum' "$file" > /dev/null
        grep -F -- '/checksum/version/jdk-21.0.13+9' "$file" > /dev/null
        grep -F -- '@playwright/mcp@0.0.84' "$file" > /dev/null
        grep -F -- 'ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pi/browsers' "$file" > /dev/null
        grep -F -- 'node "${mcp_manifest%/package.json}/cli.js" install --with-deps chromium firefox webkit' "$file" > /dev/null
        awk '/^RUN / { p=1; sub(/^RUN /, "") } p { print; if ($0 !~ /\\$/) { p=0; print "" } }' "$file" | sh -n
    fi
    # Parse the actual generated installer with a POSIX shell, without executing it.
    awk '/^RUN set -eux;/ { p=1; sub(/^RUN /, "") } p { print } /glab auth login --help/ { exit }' "$file" | sh -n
done
echo 'Standard image generation tests passed.'
