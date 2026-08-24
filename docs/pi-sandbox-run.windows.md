# pi-sandbox-run.ps1

Run existing Pi sandbox images with Podman on Windows PowerShell 7. The runner never builds missing images.

## Usage

```powershell
.\pi-sandbox-run.ps1 [PROFILE] [OPTIONS] [-- PI_ARGS...]
```

## Examples

```powershell
.\pi-sandbox-run.ps1
.\pi-sandbox-run.ps1 rust
.\pi-sandbox-run.ps1 rust --name backend
.\pi-sandbox-run.ps1 rust --workspace C:\Users\you\src\backend
.\pi-sandbox-run.ps1 rust --mount C:\Users\you\src\shared:/src:ro
.\pi-sandbox-run.ps1 rust -- --help
```

## Configuration

Configuration follows the Windows standard per-user roaming profile location:

```text
%APPDATA%\pi-sandbox\config
%APPDATA%\pi-sandbox\allowed-roots
```

If `%APPDATA%` is unavailable, the runner falls back to:

```text
%USERPROFILE%\AppData\Roaming\pi-sandbox
```

This is the Windows counterpart to the Unix XDG configuration location. Use
`--config FILE` to select another config file; its sibling `allowed-roots` file
is used automatically.

Allowed roots are absolute paths. The default is `%USERPROFILE%\src`, which is
created when first run. A workspace or mount source must be a visible, existing
directory below an allowed root; it cannot be the root itself, a reparse point,
or contain `.` / `..` traversal. Declared roots may be outside `%USERPROFILE%`.

## Runtime options

- `--name NAME` — sandbox instance name; changes the persistent state volume.
- `--workspace DIRECTORY` — Windows absolute path or `.`-relative directory to mount as the container start directory.
- `--mount SPEC` — repeatable bind mount: `C:\host\path:/container[:ro|rw]`.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
- `--memory SIZE`, `--cpus NUMBER`, `--pids-limit NUMBER` — Podman limits.
- `--no-network` — disable networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.
- `--show-state`, `--reset-state`, `--info`, `--dry-run`, `--verbose`, `--debug`, `--yes` / `-y` — inspection and control options.

A profile name maps to `pi-sandbox-PROFILE:latest`. The runner requires that
image to exist and asks an administrator to build it if absent.
