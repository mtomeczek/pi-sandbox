# pi-sandbox-create

Create and build Pi sandbox images. This command is intended for administrators or users responsible for image/profile management.

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
- `--tool TOOL@VERSION` — add a tool; repeatable. Supported tools: `go`, `rust`, `jvm`, `uv`, `fnm`, `python`. Node for Pi comes exclusively from `--base-image`.
- `--extension TYPE:SPEC` — add an extension; repeatable. Supported extensions: `rustup:COMPONENT`, `cargo:CRATE[@VERSION]`, `uv:PACKAGE[@VERSION]`, `fnm:node@VERSION`. The FNM Node extension requires `--tool fnm@VERSION` and installs only under the Pi user's FNM tree.
- `--npm PACKAGE[@VERSION]` — install a global npm command-line package; repeatable. Scoped packages such as `@angular/cli@20.3.9` are supported.
- `--env NAME=VALUE` — add an environment variable to the manifest.
- `--path DIRECTORY` — prepend a directory to `PATH` from the manifest.
- `--apt PACKAGE` — add an APT package to the image; repeatable.

## Build options

- `--build` — build the image if missing.
- `--update` — rebuild the selected image.
- `--regenerate-containerfile` — regenerate the Containerfile.
- `--no-cache` — disable Podman build cache; implies `--update`.
- `--pull` — pull a newer base image; implies `--update`.
- `--clean-image` — remove the selected sandbox image.
- `--list-images` — list locally available images carrying the `pi-sandbox` tag (repository, tag, ID, age, size) without building or changing them.

Built and reused images are additionally tagged as `REPOSITORY:pi-sandbox`; this stable management tag, rather than a repository-name convention, selects images for `--list-images`.

- `--pi-version VERSION` — Pi npm package version or dist-tag.
- `--base-image IMAGE` — base image.
- `--image IMAGE` — override image name.
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

- Config: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config`
- Profile manifests: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/profiles/PROFILE.profile`
- Generated Containerfiles: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/dockerfiles/Containerfile.pi-sandbox[.PROFILE]`
- Containerfile template: `templates/Containerfile.pi-sandbox.template`
- Profile manifest preamble template: `templates/profile.template`
