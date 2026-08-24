#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${ROOT_DIR}/test-macos-compat.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

for command in pi-sandbox-create pi-sandbox-run pi-sandbox-setup; do
	bash -n "${ROOT_DIR}/${command}"
	if grep -Eq 'realpath|readlink --|mkdir -p --|rm -[a-z]* --|ln -[a-z]* --|dirname --' "${ROOT_DIR}/${command}"; then
		printf 'GNU-only path utility usage remains in %s.\n' "$command" >&2
		exit 1
	fi
	ln -s "${ROOT_DIR}/${command}" "${WORK_DIR}/${command}"
done

if [[ ! -L "${WORK_DIR}/pi-sandbox-create" ]]; then
	printf 'macOS symlink checks skipped: filesystem does not preserve symbolic links.\n'
	exit 0
fi

cmp -s <("${WORK_DIR}/pi-sandbox-create" --help) "${ROOT_DIR}/docs/pi-sandbox-create.md"
cmp -s <("${WORK_DIR}/pi-sandbox-run" --help) "${ROOT_DIR}/docs/pi-sandbox-run.md"
cmp -s <("${WORK_DIR}/pi-sandbox-setup" --help) "${ROOT_DIR}/docs/pi-sandbox-setup.md"

printf 'macOS compatibility tests passed.\n'
