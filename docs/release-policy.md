# Release and compatibility policy

This policy defines the supported host runtime and the process for changing the generated sandbox image defaults.

## Supported Podman versions

| Host | Supported runtime | Release validation |
| --- | --- | --- |
| Linux | Podman `6.x` in rootless mode | Run the Bash regression suite and basic image build and startup test. |
| macOS | Podman Desktop whose bundled engine is Podman `6.x` | Run the Bash regression suite and macOS symlink test. |
| Windows | Podman Desktop whose bundled engine is Podman `6.x` | Run PowerShell parsing and help and mock-Podman regression checks. |

Minimum supported Podman version: `6.0.0`.

The commands deliberately require rootless Podman and working subordinate UID and GID mappings on Linux. Versions older than `6.0.0` may work but are unsupported until added to this matrix and validated in CI.

## Image defaults

The canonical defaults must stay identical in the Bash and PowerShell creators:

- Default Pi version: `1.5.0`
- Default base image: `debian:bookworm-slim`
- Private Node.js source image: `node:24.22.2-bookworm-slim` (separate build stage, copied under `/opt/pi/node`)
- GitHub CLI: `2.103.3`; GitLab CLI: `1.128.0` (checksum-verified upstream archives)
- Playwright MCP: `0.0.84`
- Default image name: `pi-sandbox:latest`

`tests/release-policy.sh` checks these cross-platform defaults and verifies that a supplied Podman version meets the declared minimum.

## Release procedure

1. Choose a Pi release with official managed-install manifests, a compatible private Node.js source image, and a runtime base image.
2. Update both creator implementations and this document in one change.
3. Regenerate a representative Containerfile and run the regression suite.
4. Build a minimal profile with the oldest supported Podman version, then start it and confirm that Pi launches with the private Node.js runtime supplied by the image, with no system-wide `node` command.
5. Repeat the relevant host validation for Linux, macOS, and Windows before publishing a release.
6. Record the validated Podman versions and the Pi and base-image changes in the release notes.

## Version updates

- **Pi patch or minor version:** update the pinned default only after a representative image build and Pi startup test pass.
- **Pi major, private Node.js source, or runtime base-image change:** additionally rebuild profiles using FNM, Rust, Python, and JVM tooling, because generated snippets and PATH initialization may be affected.
- **Podman major version:** add it to the support matrix only after rootless mounts, volumes, network disabling, and state reset behavior are exercised on each applicable host.

Users may override the Pi version and base image for individual profiles, but those overrides do not expand the project's support matrix.
