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
.\pi-sandbox-run.ps1 rust --port 3000:3000
.\pi-sandbox-run.ps1 --list-images
.\pi-sandbox-run.ps1 --init
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

## Project startup configuration

A readable, non-symlinked `.pisandboxrc` at the resolved workspace root can
set `NAME` once and repeat `PORT`, `MOUNT`, and `PI_EXTENSION`. CLI `--name`
takes precedence; CLI ports and mounts append after the project settings.
`PI_EXTENSION` entries are installed using `pi install -l`, keeping packages in
the workspace's `.pi` directory. Use `--init` to copy the standard template to
the resolved workspace; with `--name NAME`, it writes `NAME=NAME` into that
new file. It refuses to overwrite an existing `.pisandboxrc` and does not
require Podman. See
[`pi-sandbox-run.md`](pi-sandbox-run.md#project-startup-configuration) and
`templates/pisandboxrc.template` for the validated format and security notes.

## Profile token secrets

Add `ENV_SECRET=GITLAB_TOKEN=gitlab-token` and/or
`ENV_SECRET=GITHUB_TOKEN=github-token` to `profiles/PROFILE.profile` beside the
runner config. Values are existing Podman secret names, never token contents.
The runner injects the secrets as `GITLAB_TOKEN` / `GITHUB_TOKEN` environment
variables using Podman's `--secret` option. Create secrets in the same Podman
connection before starting; missing secrets cause Podman to reject startup.
Container processes and extensions can access the tokens. Dry runs print only
secret references. See the Unix runner documentation for more detail.

## Workspace Git connection

The runner derives `GH_HOST`, `GH_REPO`, `GITLAB_HOST`, `GITLAB_API_HOST`,
`GITLAB_REPO`, and `GLAB_API_PROTOCOL` from the workspace's `origin` remote
(or its first remote). It also supplies Git author/committer names and emails
from `user.name` / `user.email`. An explicit remote login is exposed only as
informational `GIT_REMOTE_USER`; it is not the authenticated service username.
Passwords and URL queries are not forwarded. No network requests are made.
Missing Git/non-repositories/local remotes are tolerated. SSH aliases and host
SSH keys/configuration are not imported.

Provide authentication separately with `--env` or profile `ENV_SECRET`; the
account username comes from the token. Profile `ENV` and explicit `--env`
options override inferred defaults. See the Unix runner's workspace Git
connection section for supported remote formats and details.

## Profile environment variables

Repeat `ENV=NAME=value` for literal environment variables and
`ENV_SECRET=NAME=podman-secret-name` for runtime Podman secret references.
The separator is `=`, not `-`; additional `=` characters in plain values are
preserved. `ENV` is also baked into images; `ENV_SECRET` is runtime-only and
must name an existing secret, never contain a token value. For example:

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
- `--memory SIZE`, `--cpus NUMBER`, `--pids-limit NUMBER` — Podman limits.
- `--no-network` — disable networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.
- `--show-state`, `--reset-state`, `--info`, `--list-images`, `--init`, `--dry-run`, `--verbose`, `--debug`, `--yes` / `-y` — inspection and control options. `--list-images` selects locally tagged `pi-sandbox` images without resolving or starting a workspace. `--init` writes the standard project configuration without starting a sandbox; `--name NAME` adds its `NAME` setting to the new file.

A profile name maps to `pi-sandbox-PROFILE:latest`. The runner requires that
image to exist and asks an administrator to build it if absent.
