#!/bin/sh
# Do not change PATH: project commands must retain their fnm-selected Node.
set -eu
root="${PI_SANDBOX_AGENT_DIR:?PI_SANDBOX_AGENT_DIR is required}/install"
IFS= read -r version < "$root/current-version"
case "$version" in
    ""|.|..|*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._+-]*)
        echo "Invalid managed Pi version" >&2; exit 1 ;;
esac
export PI_MANAGED_INSTALL_ROOT="$root"
exec /opt/pi/node/bin/node "$root/releases/$version/node_modules/.bin/pi" "$@"
