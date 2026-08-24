#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BIN_DIR="${WORK_DIR}/bin"
HOME_DIR="${WORK_DIR}/home"
export HOME="$HOME_DIR"
export XDG_BIN_HOME="$BIN_DIR"
export PATH="${BIN_DIR}:${PATH}"

mkdir -p "$BIN_DIR"
ln -s "${ROOT_DIR}/pi-sandbox-run" "${BIN_DIR}/.symlink-probe"
if [[ ! -L "${BIN_DIR}/.symlink-probe" ]]; then
	printf 'Setup tests skipped: filesystem does not preserve symbolic links.\n'
	exit 0
fi
rm "${BIN_DIR}/.symlink-probe"

canonical_existing_path() {
	local path="$1" directory name link

	case "$path" in
	/*) ;;
	*) path="$PWD/$path" ;;
	esac
	while [[ -L "$path" ]]; do
		directory="$(cd -P "$(dirname "$path")" && pwd)" || return 1
		link="$(readlink "$path")" || return 1
		case "$link" in
		/*) path="$link" ;;
		*) path="$directory/$link" ;;
		esac
	done
	[[ -e "$path" ]] || return 1
	directory="$(cd -P "$(dirname "$path")" && pwd)" || return 1
	name="$(basename "$path")"
	printf '%s/%s\n' "$directory" "$name"
}

assert_link_target() {
	local command="$1" expected="${ROOT_DIR}/$1"

	[[ -L "${BIN_DIR}/${command}" ]] || {
		printf 'Expected symlink: %s\n' "${BIN_DIR}/${command}" >&2
		return 1
	}
	[[ "$(canonical_existing_path "${BIN_DIR}/${command}")" == "$expected" ]] || {
		printf 'Unexpected target for %s\n' "$command" >&2
		return 1
	}
}

"${ROOT_DIR}/pi-sandbox-setup" --install
for command in pi-sandbox-create pi-sandbox-run pi-sandbox-setup; do
	assert_link_target "$command"
done

"${BIN_DIR}/pi-sandbox-setup" --remove
for command in pi-sandbox-create pi-sandbox-run pi-sandbox-setup; do
	[[ ! -e "${BIN_DIR}/${command}" && ! -L "${BIN_DIR}/${command}" ]] || {
		printf 'Expected removal: %s\n' "${BIN_DIR}/${command}" >&2
		exit 1
	}
done

mkdir -p "$BIN_DIR"
printf 'foreign command\n' >"${BIN_DIR}/pi-sandbox-run"
if "${ROOT_DIR}/pi-sandbox-setup" --install; then
	printf 'Installation unexpectedly replaced a regular file\n' >&2
	exit 1
fi
[[ -f "${BIN_DIR}/pi-sandbox-run" ]] || {
	printf 'Regular file was unexpectedly changed\n' >&2
	exit 1
}
for command in pi-sandbox-create pi-sandbox-setup; do
	[[ ! -e "${BIN_DIR}/${command}" && ! -L "${BIN_DIR}/${command}" ]] || {
		printf 'Installation was not atomic: %s\n' "${BIN_DIR}/${command}" >&2
		exit 1
	}
done

printf 'Setup tests passed.\n'
