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
pi-sandbox-create --create rust --tool rust@1.90.0 --extension rustup:clippy
pi-sandbox-create rust --build --pull
pi-sandbox-create rust --regenerate-containerfile --no-cache
```

## Profile management

- `--create PROFILE` — create or update a versioned profile manifest.
- `--tool TOOL@VERSION` — add a tool; repeatable. Supported tools: `go`, `rust`, `jvm`, `uv`, `fnm`, `node`, `python`.
- `--extension TYPE:SPEC` — add an extension; repeatable. Supported extensions: `rustup:COMPONENT`, `cargo:CRATE[@VERSION]`, `uv:PACKAGE[@VERSION]`.
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
- `--pi-version VERSION` — Pi npm package version or dist-tag.
- `--base-image IMAGE` — base image.
- `--image IMAGE` — override image name.
- `--container-user NAME` — runtime user name.
- `--container-uid UID` — runtime user UID.
- `--container-gid GID` — runtime user GID.

## Information

- `--info` — show resolved build configuration.
- `--dry-run` — print actions without executing them.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## Files

- Config: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config`
- Profile manifests: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/images/PROFILE.manifest`
- Generated Containerfiles: `${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/dockerfiles/Containerfile.pi-sandbox[.PROFILE]`
- Containerfile template: `templates/Containerfile.pi-sandbox.template`
- Profile manifest preamble template: `templates/profile.manifest.template`
