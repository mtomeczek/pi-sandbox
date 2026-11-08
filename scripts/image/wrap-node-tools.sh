#!/bin/bash
# Keep npm's own bin links intact; expose separate private-Node launchers.
set -euo pipefail
prefix="${1:?An npm prefix is required}"
mkdir -p "$prefix/node-bin"
for launcher in "$prefix"/bin/*; do
    [[ -L "$launcher" ]] || continue
    target="$(readlink -f "$launcher")"
    first=""
    IFS= read -r first < "$target" || true
    case "$first" in
        '#!'*node*)
            printf -v quoted '%q' "$target"
            printf '%s\n' '#!/bin/bash' "exec /opt/pi/node/bin/node $quoted \"\$@\"" > "$prefix/node-bin/${launcher##*/}"
            chmod 0755 "$prefix/node-bin/${launcher##*/}"
            ;;
    esac
done
