# pi-sandbox

Create and run isolated Pi coding-agent sandboxes with rootless Podman.

The project is split into two roles:

- **Admin/image creator**: builds versioned sandbox images and profile manifests.
- **Standard user/runner**: runs existing images only. It never builds missing images.

## Requirements

- Bash (including macOS's bundled Bash 3.2)
- Rootless Podman
- Working subordinate UID/GID mappings for rootless `keep-id` containers
- Network access during image builds

## Commands

| Command | Purpose |
| --- | --- |
| `pi-sandbox-create` | Admin command for creating profile manifests, generating Containerfiles, and building/removing images. |
| `pi-sandbox-run` | Standard-user command for running existing sandbox images. It never builds missing images. |
| `pi-sandbox-setup` | Unix-only command for installing or removing the user-local command symlinks. |

## User-local installation

Create symlinks for the Unix commands in the XDG user binary directory:

```bash
./pi-sandbox-setup --install
```

This installs:

```text
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox-create
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox-run
${XDG_BIN_HOME:-$HOME/.local/bin}/pi-sandbox-setup
```

Make sure that directory is in `PATH`. The setup command refuses to replace regular
files or unrelated symlinks, and preflights every destination before changing any of them.

Remove the installed symlinks with:

```bash
pi-sandbox-setup --remove
```

## Quick start

### Admin: create and build a profile image

```bash
./pi-sandbox-create --create rust --tool rust@1.90.0
```

This creates a profile manifest and builds:

```text
pi-sandbox-rust:latest
```

### macOS

The standard Bash commands are the macOS version; no separate launcher is required. They support the stock Bash 3.2 and BSD userland, including symlinked installation through `pi-sandbox-setup`. Start a Podman machine before creating or running sandboxes:

```bash
podman machine init  # first use only
podman machine start
./pi-sandbox-create --create rust --tool rust@1.90.0
./pi-sandbox-run rust
```

See [macOS documentation](docs/pi-sandbox-macos.md) for configuration and validation details.

### Windows PowerShell 7

Create with Windows Podman:

```powershell
.\pi-sandbox-create.ps1 --create node-legacy --tool fnm@1.39.0 --extension fnm:node@14
```

The Windows creator and runner share `%APPDATA%\pi-sandbox` (or `%USERPROFILE%\AppData\Roaming\pi-sandbox` when `%APPDATA%` is unavailable). See [Windows creator documentation](docs/pi-sandbox-create.windows.md).

### Standard user: run an existing profile image

```bash
./pi-sandbox-run rust
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

Create an Angular profile with a pinned global CLI package:

```bash
./pi-sandbox-create --create angular \
  --tool fnm@1.39.0 \
  --extension fnm:node@22 \
  --npm @angular/cli@20.3.9
```

Profiles may also contain repeatable npm directives directly:

```text
NPM=@angular/cli@20.3.9
NPM=create-vite@7.1.7
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

## Project Node runtime

The image's base Node remains the runtime for Pi itself. To give project commands a separate Node version, add FNM and pin the project runtime while creating a profile:

```bash
./pi-sandbox-create --create legacy \
  --base-image node:24-bookworm-slim \
  --tool fnm@1.39.0 \
  --extension fnm:node@14 \
  --extension fnm:node@25 \
  --env FNM_VERSION_FILE_STRATEGY=recursive
```

The generated profile uses repeatable `EXTENSION=fnm:node@VERSION` directives. The base image supplies Pi's only runtime: `/usr/local/bin/pi` is always executed with `/usr/local/bin/node`. FNM project versions are installed only below `/home/pi/.local/share/fnm/node-versions/`. At startup, the entrypoint initializes FNM and asks it to use the workspace version file; `FNM_VERSION_FILE_STRATEGY=recursive` lets FNM find `.node-version` or `.nvmrc` in a parent directory. This changes the environment inherited by project commands without changing Pi's interpreter.

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

Use a different host starting directory:

```bash
./pi-sandbox-run rust --workspace ~/src/projects/backend
```

The directory keeps its basename inside the container. In this example it is
mounted at `/home/pi/backend`, and Pi starts there. The current directory uses
the same rule when `--workspace` is omitted; no generic `/home/pi/workspace`
runtime mount is used.

Starting-directory and extra-mount sources are validated identically. They must
be existing, non-symlinked directories strictly below a configured allowed
root. They may be nested at any depth and do not need to be direct children.
Sources may be absolute or start with `./`; `./` paths are expanded against the
current directory before validation. Other relative paths are rejected. Files,
the approved roots themselves, hidden directory components, `.`/`..` traversal,
and paths outside configured roots are rejected.

Only the selected source directory and its path are validated. Its contents are
not scanned and may include hidden files/directories, regular files, and
symbolic links. Extra mount destinations must be absolute and cannot be `/`,
hidden, or contain traversal components. Mount mode is limited to `ro` or `rw`.

Allowed roots are configured one absolute path per line in:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/allowed-roots
```

The file is created automatically with `$HOME/src` as its default entry and can
be edited by hand. `$HOME/src` is created if it does not already exist. Entries
must be existing directories; filesystem roots, hidden components, `.`/`..`,
empty components, and symlinks are rejected. For example:

```text
/home/you/src
/workspaces/team-a
/mnt/shared/customer-a
```

### Project-local startup settings

A workspace can commit `.pisandboxrc` to declare a sandbox name, repeatable port
forwards and extra mounts, plus Pi package sources to install into that
workspace's `.pi/settings.json`:

```ini
NAME=backend
PORT=3000:3000
MOUNT=./shared-libs:/src/shared:ro
PI_EXTENSION=npm:@acme/pi-tools@1.2.3
```

The launcher parses this as data, never as shell code. CLI values take
precedence for the name and append after project ports/mounts. See
[`docs/pi-sandbox-run.md`](docs/pi-sandbox-run.md#project-startup-configuration)
and [`templates/pisandboxrc.template`](templates/pisandboxrc.template) for the
complete contract.

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

### Windows PowerShell 7

Use `pi-sandbox-run.ps1` with Windows Podman:

```powershell
.\pi-sandbox-run.ps1 rust --workspace C:\Users\you\src\backend
.\pi-sandbox-run.ps1 rust --mount C:\Users\you\src\shared:/src:ro
```

Its per-user configuration is stored in `%APPDATA%\pi-sandbox` (falling back to `%USERPROFILE%\AppData\Roaming\pi-sandbox`), the Windows counterpart of the XDG configuration directory. See [Windows runner documentation](docs/pi-sandbox-run.windows.md).

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
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/profiles/
```

The default config and allowed-roots files are:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/allowed-roots
```

## Templates and docs

Containerfile generation uses the base template and external dynamic snippets:

```text
templates/Containerfile.pi-sandbox.template
templates/Containerfile.snippets.template
```

Default creator/runner configuration and allowed-roots content are also external templates:

```text
templates/create.config.template
templates/run.config.template
templates/allowed-roots.template
```

New profile manifests include the explanatory preamble from:

```text
templates/profile.template
```

Help text is externalized as Markdown:

```text
docs/pi-sandbox-run.md
docs/pi-sandbox-create.md
docs/pi-sandbox-setup.md
docs/release-policy.md
```

`-h` and `--help` print the corresponding Markdown file. The [release and compatibility policy](docs/release-policy.md) defines supported Podman versions and image-default update requirements.

## Development checks

Run basic syntax checks:

```bash
bash -n pi-sandbox-run pi-sandbox-create pi-sandbox-setup
```

Verify help output is sourced from Markdown files:

```bash
cmp -s <(./pi-sandbox-run --help) docs/pi-sandbox-run.md
cmp -s <(./pi-sandbox-create --help) docs/pi-sandbox-create.md
cmp -s <(./pi-sandbox-setup --help) docs/pi-sandbox-setup.md
```

Run the setup safety regression test:

```bash
bash tests/setup.sh
bash tests/allowed-roots.sh
bash tests/macos-compat.sh
bash tests/release-policy.sh
```

Run ShellCheck locally when available (the GitHub Actions static-analysis workflow installs it on Linux and macOS):

```bash
shellcheck --shell=bash --severity=warning pi-sandbox-create pi-sandbox-run pi-sandbox-setup tests/*.sh
```

Run the matching Windows static analysis with the checked-in settings:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path .\pi-sandbox-create.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\pi-sandbox-run.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
```

Validate the Windows PowerShell launchers and their help contracts:

```powershell
pwsh -NoProfile -File .\pi-sandbox-create.ps1 --help | Compare-Object (Get-Content .\docs\pi-sandbox-create.windows.md)
pwsh -NoProfile -File .\pi-sandbox-run.ps1 --help | Compare-Object (Get-Content .\docs\pi-sandbox-run.windows.md)
```

## Author

Michal Tomeczek <mtomeczek74@gmail.com>

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the
full license text.
