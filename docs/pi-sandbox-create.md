# pi-sandbox-create

Create and build Pi sandbox images. This command is intended for administrators and users who manage images and profiles.

All images include GitHub CLI (`gh`) from Debian and GitLab CLI (`glab`) v1.124.0 for amd64 and arm64. The glab archive is verified against the release's SHA-256 checksum. Builds verify that `glab auth login` supports `--device`. For existing images, use `pi-sandbox-create PROFILE --regenerate-containerfile --update` to apply the updated standard tools. Authenticate using host `--env` options or profile `ENV_SECRET` references; credentials are not included in the image.

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

```text
pi-sandbox-create --build [OPTIONS]
pi-sandbox-create --create PROFILE --tool TOOL@VERSION [OPTIONS]
pi-sandbox-create PROFILE --build [OPTIONS]
```

## Examples

```bash
pi-sandbox-create --build
pi-sandbox-create --create node-legacy --tool fnm@1.39.0 --extension fnm:node@14 --extension fnm:node@25 --env FNM_VERSION_FILE_STRATEGY=recursive
pi-sandbox-create rust --build --pull
pi-sandbox-create rust --regenerate-containerfile --no-cache
pi-sandbox-create --list-images
```

## Profile management

- `--create PROFILE` — create or update a versioned profile manifest.
- `--tool TOOL@VERSION` — add a tool; repeatable. Supported tools: `go`, `rust`, `jvm`, `uv`, `fnm`, `python`, `caddy`, and `playwright`. Caddy downloads its requested release into the Pi user's XDG bin directory. Playwright installs its CLI and `@playwright/mcp`, along with the Chromium, Firefox, and WebKit browsers and their dependencies. Node for Pi comes exclusively from `--base-image`.
- `--extension TYPE:SPEC` — add an extension; repeatable. Supported extensions: `rustup:COMPONENT`, `cargo:CRATE[@VERSION]`, `uv:PACKAGE[@VERSION]`, and `fnm:node@VERSION`. The FNM Node extension requires `--tool fnm@VERSION` and installs only under the Pi user's FNM directory.
- `--npm PACKAGE[@VERSION]` — install a global npm command-line package; repeatable. Scoped packages such as `@angular/cli@20.3.9` and version ranges such as `playwright@^1.55.0` are supported.
- `--env NAME=VALUE` — add an environment variable to the manifest as `ENV=NAME=VALUE`; the value is included in the image and passed by the runner. For runtime-only secrets, add `ENV_SECRET=NAME=PODMAN_SECRET_NAME` to the profile instead; never use actual token values.
- `--path DIRECTORY` — prepend a directory to `PATH` from the manifest.
- `--apt PACKAGE` — add an APT package to the image; repeatable.
- `--shell-command COMMAND` — add a trusted, one-line shell command to run during the image build as the Pi user; repeatable. Commands are persisted in the profile and emitted as Containerfile `RUN` instructions. Use `--apt` to install Debian packages as root.

## Build options

- `--build` — build the image if missing.
- `--update` — rebuild the selected image.
- `--regenerate-containerfile` — regenerate the Containerfile.
- `--no-cache` — disable the Podman build cache; implies `--update`.
- `--pull` — pull a newer base image; implies `--update`.
- `--clean-image` — remove the selected sandbox image.
- `--list-images` — list locally available images carrying the `pi-sandbox` tag (repository, tag, ID, age, size) without building or changing them.

Images built or reused by the creator receive an additional `REPOSITORY:pi-sandbox` tag. The `--list-images` option selects this tag rather than relying on repository naming conventions.

## Image settings

- `--pi-version VERSION` — Pi npm package version or distribution tag.
- `--base-image IMAGE` — select the base image.
- `--image IMAGE` — override the image name.
- `--container-user NAME` — runtime user name.
- `--container-uid UID` — runtime user UID.
- `--container-gid GID` — runtime user GID.

## Setup

Install or remove the user-local command symlinks with `pi-sandbox-setup`. See `pi-sandbox-setup --help` for details.

## Information

- `--info` — show resolved build configuration.
- `--dry-run` — print actions without executing them.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## Files

- Configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config`
- Profile manifests: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/profiles/PROFILE.profile`
- Generated Containerfiles: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/dockerfiles/Containerfile.pi-sandbox[.PROFILE]`
- Containerfile template: `templates/Containerfile.pi-sandbox.template`
- Profile manifest preamble template: `templates/profile.template`
