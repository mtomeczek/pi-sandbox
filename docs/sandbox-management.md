# Sandbox creation and startup management

These features are available in the Bash and PowerShell creators and runners. On Windows, use `pi-sandbox-create.ps1` and `pi-sandbox-run.ps1` instead of the Bash commands. Python **3.9+** is required on the host for pre-build validation, version management, and `--doctor`. Ordinary sandbox startup does not require Python.

## Validate, preview, then build

```bash
pi-sandbox-create golang --validate
pi-sandbox-create golang --validate --online
pi-sandbox-create golang --tool go@1.27.3 --pi-version 1.4.0 --update --dry-run
pi-sandbox-create golang --regenerate-containerfile --update
```

Settings are applied in this order: defaults, global configuration, profile, then command-line options. A CLI `--tool name@version` replaces that tool's profile entry. Overrides affect only the current invocation; they do not modify the saved manifest. Additional extension, npm, `ENV`, `PATH`, `APT`, and shell-command options are applied after the profile and trigger Containerfile regeneration.

Each image-creation invocation validates the effective profile before writing a manifest or building an image. Offline validation rejects malformed tool names or versions, control characters, duplicate tools, invalid npm specifications, and missing dependencies (Python requires uv; cargo and rustup extensions require Rust; fnm extensions require fnm). Tool versions must be numeric; fnm and Caddy also accept a leading `v`.

`--validate --online` additionally checks supported fixed tool and npm package versions against upstream services. It requires network access and stops the operation if an upstream lookup fails. It does not authenticate to custom base-image registries or evaluate arbitrary shell commands.

`ENV` values are plain build settings, not shell snippets: double quotation marks, backslashes, backticks, and `$` expansion are rejected. Use `PATH` for supported path-variable references, or a trusted `--shell-command` for explicit shell commands. Shell commands must be one non-empty line and cannot end in a continuation backslash. Always review profile shell commands before building a profile from another source.

Replacing an existing manifest with `--create` requires confirmation (`--yes` for noninteractive use) and makes a timestamped backup. Edit the existing profile to preserve overrides and runtime secret directives. Replacing it with a partial command-line definition can omit those settings.

A cached Containerfile without the current revision marker, or older than its profile, template, or snippets, is rejected before a build, with instructions to use `--regenerate-containerfile --update`.

Images carry profile, Pi, tool and npm package version, template revision, capability, and build-time labels. Archive downloads for Go, the JDK, Caddy, and glab are checked against upstream checksums (SHA-256 or SHA-512, depending on the release). Go hashes come from the official release JSON metadata. Rustup, uv, and fnm still use upstream installers; these external dependencies prevent a guarantee of fully reproducible builds. Playwright MCP uses the independently specified version `0.0.83`; browser versions correspond to the selected Playwright release.

## Audit and upgrade a saved profile

```bash
pi-sandbox-create golang --check-updates
pi-sandbox-create golang --check-updates --patch-only
pi-sandbox-create golang --upgrade --patch-only --dry-run
pi-sandbox-create golang --upgrade --patch-only --yes
```

Audits show **only component names and version changes**, never environment-variable values or secret contents. Upgrades require confirmation, preserve comments and non-version settings, create a timestamped `.bak-*` backup alongside the manifest, and atomically replace the file. Failed lookups do not partially update the manifest. Detected concurrent edits and symlinked upgrade targets are rejected.

Updates stay within the current major version. `--patch-only` additionally preserves the minor version, which is useful for language compatibility. Floating versions (`latest`, Node `14`) and npm ranges are retained, not silently pinned. The updater covers Pi, supported tools, pinned npm packages, and fnm-managed Node versions. Base image tags, APT packages, arbitrary shell installers, and other extension managers remain manually managed. GitHub version checks examine the latest 100 release records and exclude drafts and prereleases. An audit is not a vulnerability scanner.

No version-management command rebuilds an image automatically. After reviewing changes, run `pi-sandbox-create PROFILE --regenerate-containerfile --update`. Existing containers continue using their original images. Updated images are used only when new containers are created.

## Workspace defaults

```ini
PROFILE=golang
NAME=backend
PORT=3000:3000
```

Save these settings in the workspace's declarative `.pisandboxrc`, or initialize the file with:

```bash
pi-sandbox-run golang --init --name backend
pi-sandbox-run
```

`PROFILE` is allowed once. An explicit CLI profile or `--image` takes precedence. This file is never sourced or evaluated as shell code.

## Optional persistent CLI authentication

```bash
pi-sandbox-run golang --persist-cli-auth --shell
# Inside the container, only when needed:
gh auth login
glab auth login --hostname gitlab.com --device
```

Opt-in persistence uses two named volumes derived from the Pi state volume:

- `STATE-gh-auth` is mounted at `$CONTAINER_HOME/.config/gh`.
- `STATE-glab-auth` is mounted at `$CONTAINER_HOME/.config/glab-cli`.

Instance names and an explicit `--state-volume` setting therefore determine which sandboxes share credentials. Continue using `--persist-cli-auth` on subsequent runs to reuse them.

No CLI login, host Git inspection, token copying, or CLI environment injection happens automatically. Environment variables that override a CLI's configuration directory can cause it to use a different location from these mount points.

**These volumes can contain plaintext credentials.** Protect access to your rootless Podman account and storage. A separate volume does not isolate credentials from processes inside the sandbox. Review extensions and workspace code before mounting authentication data.

```bash
pi-sandbox-run golang --reset-cli-auth --dry-run
pi-sandbox-run golang --reset-cli-auth --yes
```

Reset deletes only these two CLI authentication volumes, not Pi state. It requires confirmation; Podman refuses removal while a volume is in use.

## Diagnose without starting containers

```bash
pi-sandbox-run golang --doctor
pi-sandbox-run golang --doctor --dry-run
```

The `--doctor` action validates the workspace, allowed roots, mounts, environment-file readability, and ports. It then checks Podman connectivity, rootless operation, image availability, image capability labels, the existence of referenced secrets, and local port availability.

It never reads secret contents, starts a container, or creates or removes a volume. Metadata warnings explain how to regenerate the Containerfiles and rebuild outdated images; capability labels record build-time checks rather than executing tools during diagnostics.

Port checks are local and best-effort: a remote Podman host may have different port availability, and another process can acquire a port after a check. `--doctor` cannot be combined with reset or other action modes.

Verbose output and dry-run previews redact literal values in the generated Podman `--env NAME=value` arguments. Host environment-variable names and Podman secret references remain visible. Normal run output summarizes the selected profile, ports, and optional authentication persistence. Extension installation stops at the first failure. If any `pi install -l` command fails, subsequent extensions and the main agent are not started. `--shell` overrides the image entrypoint before the image argument on both platforms.
