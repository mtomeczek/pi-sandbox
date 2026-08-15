# pi-sandbox

Create and run isolated Pi coding-agent sandboxes with Podman.

## Commands

- `pi-sandbox-create` — administrator command for creating manifests, generating Containerfiles, and building/removing images.
- `pi-sandbox-run` — standard-user command for running existing sandbox images. It never builds missing images.
- `pi-sandbox` — runtime-only alias for `pi-sandbox-run`. It never dispatches to admin/build functionality.

## Examples

```bash
# Admin: create/build a Rust sandbox image
./pi-sandbox-create --create rust --tool rust@1.90.0

# Standard user: run the existing Rust image
./pi-sandbox-run rust

# Standard user: run with extra bind mounts and Pi args
./pi-sandbox-run rust --mount ~/src:/src:ro -- --help
```

Generated Containerfiles are written to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/dockerfiles/
```

New profile manifests include the explanatory preamble from:

```text
templates/profile.manifest.template
```
