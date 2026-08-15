# pi-sandbox

Create and run isolated Pi coding-agent sandboxes with rootless Podman.

The project is split into two roles:

- **Admin/image creator**: builds versioned sandbox images and profile manifests.
- **Standard user/runner**: runs existing images only. It never builds missing images.

## Requirements

- Bash
- Rootless Podman
- Working subordinate UID/GID mappings for rootless `keep-id` containers
- Network access during image builds

## Commands

| Command | Purpose |
| --- | --- |
| `pi-sandbox-create` | Admin command for creating profile manifests, generating Containerfiles, and building/removing images. |
| `pi-sandbox-run` | Standard-user command for running existing sandbox images. It never builds missing images. |
| `pi-sandbox` | Runtime-only alias for `pi-sandbox-run`. It never dispatches to admin/build functionality. |

## User-local installation

Create symlinks for all commands in the XDG user binary directory:

```bash
./pi-sandbox --install
```

This installs:

```text
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox-run
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox-create
```

Make sure that directory is in `PATH`. The installer refuses to replace regular
files or unrelated symlinks.

Remove the installed symlinks with:

```bash
pi-sandbox --remove
```

The same `--install` and `--remove` options are accepted by all three commands.

## Quick start

### Admin: create and build a profile image

```bash
./pi-sandbox-create --create rust --tool rust@1.90.0
```

This creates a profile manifest and builds:

```text
pi-sandbox-rust:latest
```

### Standard user: run an existing profile image

```bash
./pi-sandbox-run rust
```

or via the runtime alias:

```bash
./pi-sandbox rust
```

### Run with extra mounts

```bash
./pi-sandbox-run rust --mount ~/src/shared-libs:/src:ro
./pi-sandbox-run rust --mount ./shared-libs:/src:ro
```

### Pass arguments to Pi

Use `--` to stop sandbox option parsing:

```bash
./pi-sandbox-run rust -- --help
```

## Admin usage

Create/update a profile manifest and image:

```bash
./pi-sandbox-create --create rust \
  --tool rust@1.90.0 \
  --extension rustup:clippy \
  --extension rustup:rustfmt \
  --apt build-essential
```

Build an existing profile if the image is missing:

```bash
./pi-sandbox-create rust --build
```

Force rebuild:

```bash
./pi-sandbox-create rust --update --pull
```

Regenerate the Containerfile:

```bash
./pi-sandbox-create rust --regenerate-containerfile
```

Show resolved build configuration:

```bash
./pi-sandbox-create rust --info
```

## Runner usage

Run the default image:

```bash
./pi-sandbox-run
```

Run a profile image:

```bash
./pi-sandbox-run rust
```

Use a named state instance:

```bash
./pi-sandbox-run rust --name backend
```

Use a different host workspace:

```bash
./pi-sandbox-run rust --workspace ~/SAPDevelop/projects/backend
```

Workspace and extra-mount sources must be existing, non-symlinked directories
strictly below `$HOME/SAPDevelop` or `$HOME/src`. They may be nested at any
depth and do not need to be direct children. Sources may be absolute or start
with `./`; `./` paths are expanded against the current directory before
validation. Other relative paths are rejected. Files, the approved roots
themselves, hidden directory components, `.`/`..` traversal, and paths outside
those roots are rejected.

Only the selected source directory and its path are validated. Its contents are
not scanned and may include hidden files/directories, regular files, and
symbolic links. Extra mount destinations must be absolute and cannot be `/`,
hidden, or contain traversal components. Mount mode is limited to `ro` or `rw`.

Run with no network:

```bash
./pi-sandbox-run rust --no-network
```

Start a shell instead of Pi:

```bash
./pi-sandbox-run rust --shell
```

Show resolved runtime configuration:

```bash
./pi-sandbox-run rust --info
```

## Profiles

A positional profile name maps to an image name:

```text
rust -> pi-sandbox-rust:latest
```

The runner does not build missing images. If the selected image does not exist,
ask an administrator to create it with `pi-sandbox-create`.

## Generated files

Generated Containerfiles are written to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/dockerfiles/
```

Profile manifests are written to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/images/
```

The default config file is:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config
```

## Templates and docs

Containerfile generation uses:

```text
templates/Containerfile.pi-sandbox.template
```

New profile manifests include the explanatory preamble from:

```text
templates/profile.manifest.template
```

Help text is externalized as Markdown:

```text
docs/pi-sandbox-run.md
docs/pi-sandbox-create.md
docs/pi-sandbox.md
```

`-h` and `--help` print the corresponding Markdown file.

## Development checks

Run basic syntax checks:

```bash
bash -n pi-sandbox pi-sandbox-run pi-sandbox-create
```

Verify help output is sourced from Markdown files:

```bash
cmp -s <(./pi-sandbox-run --help) docs/pi-sandbox-run.md
cmp -s <(./pi-sandbox-create --help) docs/pi-sandbox-create.md
```
