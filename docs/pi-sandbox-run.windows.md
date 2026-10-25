# pi-sandbox-run.ps1

Run existing Pi sandbox images with Podman and PowerShell 7 on Windows. The runner never builds missing images.

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
.\pi-sandbox-run.ps1 rust --port 3000:3000
.\pi-sandbox-run.ps1 --list-images
.\pi-sandbox-run.ps1 --init
.\pi-sandbox-run.ps1 rust -- --help
```

## Configuration

On Windows, per-user configuration is stored in the roaming profile location:

```text
%APPDATA%\pi-sandbox\config
%APPDATA%\pi-sandbox\allowed-roots
```

If `%APPDATA%` is unavailable, the runner falls back to:

```text
%USERPROFILE%\AppData\Roaming\pi-sandbox
```

This is the Windows counterpart to the Unix XDG configuration location. Use `--config FILE` to select another configuration file; its sibling `allowed-roots` file is used automatically.

Allowed roots are absolute paths. The default root is `%USERPROFILE%\src`, which is created on the first normal run. A workspace or mount source must be a visible, existing directory below an allowed root. It cannot be the root itself, have reparse-point components, or contain `.` or `..` traversal components. Declared roots may be outside `%USERPROFILE%`.

## Project startup configuration

A readable, non-symlinked `.pisandboxrc` at the resolved workspace root can define `PROFILE` and `NAME` once each, with repeatable `PORT`, `MOUNT`, and `PI_EXTENSION` settings. An explicit command-line profile or `--image` takes precedence over the profile declared in `.pisandboxrc`. CLI `--name` takes precedence; CLI ports and mounts append after the project settings. `PI_EXTENSION` entries are installed using `pi install -l`, keeping packages in the workspace's `.pi` directory. Use `--init` to copy the standard template to the resolved workspace; for example, `--name backend` writes `NAME=backend` into the new file. It refuses to overwrite an existing `.pisandboxrc` and does not require Podman. See [`pi-sandbox-run.md`](pi-sandbox-run.md#project-startup-configuration) and `templates/pisandboxrc.template` for the validated format and security notes.

## Profile token secrets

Add `ENV_SECRET=GITLAB_TOKEN=gitlab-token`, `ENV_SECRET=GITHUB_TOKEN=github-token`, or both to `profiles/PROFILE.profile` alongside the runner configuration file. Values are existing Podman secret names, never token contents. The runner injects the secrets as `GITLAB_TOKEN` / `GITHUB_TOKEN` environment variables using Podman's `--secret` option. Create secrets in the same Podman connection before starting; missing secrets cause Podman to reject startup. Container processes and extensions can access the tokens. Dry runs print only secret references. See the Unix runner documentation for more detail.

## GitHub and GitLab authentication

The image includes `gh` and `glab`, but the runner does not infer CLI settings, Git identity, or credentials from the workspace. Authenticate inside the sandbox when needed:

```bash
gh auth login
glab auth login --hostname gitlab.com --device
```

Device login displays a URL and code to open in your host browser, without requiring a browser callback inside the container. It requires GitLab 17.9 or later; replace `gitlab.com` with your own instance as appropriate.

CLI login configuration is not persisted by the Pi state volume. Use `--persist-cli-auth` for separate, opt-in credential volumes (which can hold plaintext credentials), and `--reset-cli-auth` to delete them after confirmation. For noninteractive authentication, explicitly configure `--env NAME`, profile `ENV`, or `ENV_SECRET`; the runner does not add these settings automatically.

## Profile environment variables

Repeat `ENV=NAME=value` for literal environment variables and `ENV_SECRET=NAME=podman-secret-name` for runtime Podman secret references. The separator is `=`, not `-`; additional `=` characters in plain values are preserved. `ENV` is also included in images; `ENV_SECRET` is runtime-only and must name an existing secret, never contain a token value. For example:

```ini
ENV=APP_MODE=development
ENV_SECRET=API_TOKEN=my-api-token
```

## Runtime options

- `--name NAME` — sandbox instance name; changes the persistent state volume.
- `--workspace DIRECTORY` — Windows absolute path or `.`-relative directory to mount as the container start directory.
- `--mount SPEC` — repeatable bind mount: `C:\host\path:/container[:ro|rw]`.
- `--port SPEC` — repeatable port forward: `HOST_PORT:CONTAINER_PORT[/tcp|udp]`.
- `--env NAME` — inherit an exported host environment variable through Podman; repeatable (for example, `--env GITHUB_TOKEN --env HTTP_PROXY`). Only names appear in command logs. Unset host variables are not passed; empty values are preserved. Values are available to container processes and extensions.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
- `--persist-cli-auth` — opt into named volumes for `gh` and `glab` configuration and credentials.
- `--reset-cli-auth` — delete these volumes after confirmation; supports `--yes` and `--dry-run`.
- `--doctor` — check the workspace, Podman, image metadata, secret references, and local ports without starting a container; requires Python 3.9+. See [sandbox management](sandbox-management.md).
- `--memory SIZE`, `--cpus NUMBER`, `--pids-limit NUMBER` — Podman limits.
- `--no-network` — disable networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.
- `--show-state`, `--reset-state`, `--info`, `--list-images`, `--init`, `--dry-run`, `--verbose`, `--debug`, `--yes` / `-y` — inspection and control options. `--list-images` selects locally tagged `pi-sandbox` images without resolving or starting a workspace. `--init` writes the standard project configuration without starting a sandbox; `--name NAME` adds its `NAME` setting to the new file.

A profile name maps to `pi-sandbox-PROFILE:latest`. The runner requires that image to exist and asks an administrator to build it if absent.
