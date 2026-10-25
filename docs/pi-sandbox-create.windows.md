# pi-sandbox-create.ps1

Create and build Pi sandbox images with Windows Podman and PowerShell 7.

All images include GitHub CLI (`gh`) from Debian and GitLab CLI (`glab`) v1.124.0 for amd64 and arm64. The glab archive is verified against the release's SHA-256 checksum. Builds verify that `glab auth login` supports `--device`. For existing images, use `pi-sandbox-create.ps1 PROFILE --regenerate-containerfile --update` to apply the updated standard tools. Authenticate using host `--env` options or profile `ENV_SECRET` references; credentials are not included in the image.

## Validation and version management

Python 3.9 or later is required on the host for pre-build validation, version audits, and profile updates. Normal container startup does not require Python.

- `--validate` — validate the effective profile without building or writing it.
- `--online` — also verify the availability of supported tool and npm package versions at their upstream sources.
- `--check-updates` — audit an existing profile; no file changes.
- `--upgrade` — show proposed updates, then modify the profile after confirmation and create a backup without rebuilding the image.
- `--patch-only` — retain the current major and minor versions when proposing updates.
- `--dry-run` — preview an upgrade without changing the profile.

Command-line values take precedence over saved profile settings. This includes `--pi-version` and the version of a tool selected with `--tool`. Replacing an existing manifest requires confirmation and creates a backup. Outdated cached Containerfiles require `--regenerate-containerfile --update`. See [sandbox management](sandbox-management.md) for compatibility policy, validation rules, reproducibility limits, and complete examples.

## Usage

```powershell
.\pi-sandbox-create.ps1 --build [OPTIONS]
.\pi-sandbox-create.ps1 --create PROFILE --tool TOOL@VERSION [OPTIONS]
.\pi-sandbox-create.ps1 PROFILE --build [OPTIONS]
```

## Examples

```powershell
.\pi-sandbox-create.ps1 --build
.\pi-sandbox-create.ps1 --create node-legacy --tool fnm@1.39.0 --extension fnm:node@14 --env FNM_VERSION_FILE_STRATEGY=recursive
.\pi-sandbox-create.ps1 rust --build --pull
.\pi-sandbox-create.ps1 rust --regenerate-containerfile --no-cache
.\pi-sandbox-create.ps1 --list-images
```

## Configuration

The Windows creator shares the runner's standard per-user configuration:

```text
%APPDATA%\pi-sandbox\config
%APPDATA%\pi-sandbox\profiles\PROFILE.profile
%APPDATA%\pi-sandbox\dockerfiles\Containerfile.pi-sandbox[.PROFILE]
```

It falls back to `%USERPROFILE%\AppData\Roaming\pi-sandbox` if `%APPDATA%` is unavailable. This is the Windows equivalent of the Unix XDG configuration directory. Use `--config FILE` to select another configuration file.

## Options

- `--create PROFILE` — create or update a profile manifest.
- `--tool TOOL@VERSION` — repeatable tool: `go`, `rust`, `jvm`, `uv`, `fnm`, `python`, `caddy`, or `playwright`. Caddy downloads its requested release into the Pi user's XDG bin directory.
- `--extension TYPE:SPEC` — repeatable extension: `rustup:COMPONENT`, `cargo:CRATE[@VERSION]`, `uv:PACKAGE[@VERSION]`, or `fnm:node@VERSION`.
- `--npm PACKAGE[@VERSION]`, `--env NAME=VALUE`, `--path DIRECTORY`, `--apt PACKAGE`, `--shell-command COMMAND` — repeatable profile directives. Shell commands must be trusted, one-line commands and run as the Pi user during the image build.
- `--build`, `--update`, `--regenerate-containerfile`, `--no-cache`, `--pull`, `--clean-image`, `--list-images` — image actions. The creator assigns managed images a `pi-sandbox` tag; `--list-images` selects only that tag.
- `--pi-version VERSION`, `--base-image IMAGE`, `--image IMAGE`, `--container-user NAME`, `--container-uid UID`, `--container-gid GID` — build settings.
- `--info`, `--dry-run`, `--verbose` / `--debug`, `--yes` / `-y`, `--help` / `-h` — inspection and control options.

The creator requires Windows Podman, but `--dry-run` prints the planned actions without executing Podman.
