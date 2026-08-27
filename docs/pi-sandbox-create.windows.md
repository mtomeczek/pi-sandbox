# pi-sandbox-create.ps1

Create and build Pi sandbox images with Windows Podman and PowerShell 7.

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

It falls back to `%USERPROFILE%\AppData\Roaming\pi-sandbox` if `%APPDATA%` is unavailable. This is the Windows equivalent of the Unix XDG configuration directory. Use `--config FILE` to select another config file.

## Options

- `--create PROFILE` — create or update a profile manifest.
- `--tool TOOL@VERSION` — repeatable tool: `go`, `rust`, `jvm`, `uv`, `fnm`, or `python`.
- `--extension TYPE:SPEC` — repeatable extension: `rustup:COMPONENT`, `cargo:CRATE[@VERSION]`, `uv:PACKAGE[@VERSION]`, or `fnm:node@VERSION`.
- `--npm PACKAGE[@VERSION]`, `--env NAME=VALUE`, `--path DIRECTORY`, `--apt PACKAGE` — repeatable profile directives.
- `--build`, `--update`, `--regenerate-containerfile`, `--no-cache`, `--pull`, `--clean-image`, `--list-images` — image actions. The creator assigns managed images a `pi-sandbox` tag; `--list-images` selects only that tag.
- `--pi-version VERSION`, `--base-image IMAGE`, `--image IMAGE`, `--container-user NAME`, `--container-uid UID`, `--container-gid GID` — build settings.
- `--info`, `--dry-run`, `--verbose` / `--debug`, `--yes` / `-y`, `--help` / `-h` — inspection and control options.

The creator requires Windows Podman, but `--dry-run` prints the generated action without executing Podman.
