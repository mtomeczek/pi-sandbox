#!/bin/sh
# npm/npx are available without publishing a system-wide node executable.
set -eu
case "${0##*/}" in
    npm) cli=npm-cli.js ;;
    npx) cli=npx-cli.js ;;
    *) echo "Invoke this launcher as npm or npx" >&2; exit 1 ;;
esac
export PATH="$PATH:/opt/pi/node/bin"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/npm}"
exec /opt/pi/node/bin/node "/opt/pi/node/lib/node_modules/npm/bin/$cli" "$@"
