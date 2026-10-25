# pi-sandbox-run

Run existing Pi sandbox images. This command is intended for standard users and never builds missing images.

## Usage

```text
pi-sandbox-run [PROFILE] [OPTIONS] [-- PI_ARGS...]
```

## Examples

```bash
pi-sandbox-run
pi-sandbox-run rust
pi-sandbox-run rust --name backend
pi-sandbox-run rust --mount ~/src/shared-libs:/src:ro
pi-sandbox-run rust --mount ./shared-libs:/src:ro
pi-sandbox-run rust --port 3000:3000
pi-sandbox-run --list-images
pi-sandbox-run --init
pi-sandbox-run rust -- --help
```

## Runtime options

- `--name NAME` — sandbox instance name; changes the persistent state volume.
- `--workspace DIRECTORY` — host directory mounted as the starting directory. Defaults to the current directory. It must satisfy the host-directory restrictions below. Inside the container it is mounted under `$CONTAINER_HOME` with the same basename.
- `--mount SPEC` — add a bind mount; repeatable. Format: `HOST:CONTAINER[:ro|rw]`. Both paths are validated as described below.
- `--port SPEC` — publish a container port; repeatable. Format: `HOST_PORT:CONTAINER_PORT[/tcp|udp]`.
- `--env NAME` — inherit an exported host environment variable through Podman; repeatable (for example, `--env GITHUB_TOKEN --env HTTP_PROXY`). Only names appear in command logs. Unset host variables are not passed; empty values are preserved. Values are available to container processes and extensions.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
- `--persist-cli-auth` — opt into dedicated named volumes for `gh` and `glab` configuration. These volumes may store plaintext credentials.
- `--reset-cli-auth` — remove these CLI authentication volumes after confirmation; supports `--dry-run` and `--yes`.
- `--doctor` — validate runtime settings and check Podman, images, secret references, and local ports without starting a container. Requires Python 3.9+.
- `--memory SIZE` — container memory limit, for example `4g`.
- `--cpus NUMBER` — CPU limit, for example `4` or `2.5`.
- `--pids-limit NUMBER` — maximum number of processes.
- `--no-network` — disable container networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.

## Setup

Install or remove the user-local command symlinks with `pi-sandbox-setup`. See `pi-sandbox-setup --help` for details.

## State and information

- `--show-state` — show persistent state-volume information.
- `--reset-state` — delete persistent Pi state after confirmation.
- `--info` — show resolved runtime configuration.
- `--list-images` — list locally available images carrying the `pi-sandbox` tag (repository, tag, ID, age, size) without starting one. `pi-sandbox-create` assigns this tag when it builds or reuses an image.
- `--init` — create the standard `.pisandboxrc` in the resolved workspace. For example, `--name backend` writes `NAME=backend` into the file. It refuses to overwrite an existing path and does not require Podman.
- `--dry-run` — preview actions and resolved settings without running containers; literal environment values are redacted.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## GitHub and GitLab authentication

The image includes `gh` and `glab`, but the runner does not infer CLI settings, Git identity, or credentials from the workspace. Authenticate inside the sandbox when needed:

```bash
gh auth login
glab auth login --hostname gitlab.com --device
```

Device login displays a URL and code to open in your host browser, without requiring a browser callback inside the container. It requires GitLab 17.9 or later; replace `gitlab.com` with your own instance as appropriate.

CLI login configuration is not persisted by the Pi state volume. Use `--persist-cli-auth` for separate, opt-in credential volumes, and `--reset-cli-auth` to delete them. See [sandbox management](sandbox-management.md) for credential-storage risks, diagnostics, and examples. For noninteractive authentication, explicitly configure `--env NAME`, profile `ENV`, or `ENV_SECRET`; the runner does not add these settings automatically.

## Profile environment variables

Profile manifests support repeatable directives with `=` separators:

```ini
ENV=APP_MODE=development
ENV=API_URL=https://example.test/?a=b
ENV_SECRET=API_TOKEN=my-api-token
```

`ENV` passes a literal value using `--env NAME=value` (and is also included in images by the creator). `ENV_SECRET` references an existing Podman secret using `--secret my-api-token,type=env,target=API_TOKEN`; it is runtime-only. Never put actual tokens in `ENV` or profile files. Names must be valid environment variable identifiers. Additional `=` characters in plain values are preserved; `-` is not a separator. Empty plain values are allowed. Secret names must be non-empty and contain only letters, digits, `.`, `_`, or `-`, starting with a letter or digit.

## Profile token secrets

In the selected `profiles/PROFILE.profile` alongside the runner configuration file, declare existing Podman secret names (not token values):

```ini
ENV_SECRET=GITLAB_TOKEN=gitlab-token
ENV_SECRET=GITHUB_TOKEN=github-token
```

Create the secrets once using Podman, for example from exported host variables:

```bash
printf '%s' "$GITLAB_TOKEN" | podman secret create gitlab-token -
printf '%s' "$GITHUB_TOKEN" | podman secret create github-token -
```

The runner adds `--secret NAME,type=env,target=GITLAB_TOKEN` (or `GITHUB_TOKEN`) only for declared entries. Secrets must exist in the same Podman connection used by the runner; Podman fails startup if one is missing. Values are never written to images or profile files. Container processes, including Pi extensions, can access the resulting environment variables. `--dry-run` prints references only and does not read or create secrets.

## Project startup configuration

If the resolved workspace contains a readable `.pisandboxrc` file that is not a symbolic link, the runner applies its settings before the sandbox starts. This makes shareable project startup settings explicit without executing repository-controlled shell code:

```ini
NAME=backend
PORT=3000:3000
PORT=9229:9229/tcp
MOUNT=./shared-libs:/src/shared:ro
PI_EXTENSION=npm:@acme/pi-tools@1.2.3
PI_EXTENSION=./tools/local-pi-package
```

`PROFILE=golang` selects the default image profile and may appear once; an explicit CLI profile or `--image` takes precedence. `--init` with a positional profile writes this setting into the new file. `NAME` is allowed once. `PORT`, `MOUNT`, and `PI_EXTENSION` are repeatable. Global configuration is applied first, then `.pisandboxrc`, then CLI options; therefore `--name` takes precedence over `NAME`, while CLI mounts and ports are appended.

Each port number must be from 1 through 65535. Extensions are installed with `pi install -l` in the workspace before Pi starts, so Pi records them in `.pi/settings.json` and keeps packages project-local. Extension sources must be `npm:`, `git:`, `http(s):`, or an existing workspace-relative `./` path. Extensions can use the permissions and credentials available inside the container, so review and trust every declared source. `--dry-run` prints the install command without running it.

Run `pi-sandbox-run --init` to copy the standard template into the resolved workspace. Add `--name backend` to write `NAME=backend` into the new file. The command does not replace an existing `.pisandboxrc`. You can also use `templates/pisandboxrc.template` directly.

## Starting directory

The selected host directory keeps its name inside the container. For example:

```text
$HOME/src/team/backend -> /home/pi/backend
```

Pi starts in `/home/pi/backend`, not in a generic `workspace` directory. The same rule applies when the starting directory is selected with `--workspace`.

## Bind-mount restrictions

The starting directory and every extra bind-mount source are validated in the same way. Each source must:

- be an existing directory, not a file;
- be a strict subdirectory of a root listed in the `allowed-roots` file;
- use an absolute path or start with `./`; `./` paths are expanded from the current directory before all other checks;
- resolve to a canonical path;
- contain no symbolic-link components;
- contain no `.` or `..` traversal components;
- contain no hidden directory component whose name starts with `.`.

The source may be nested at any depth below an approved root; it does not need to be a direct child. The approved roots themselves cannot be mounted. For example, with the default `$HOME/src` root, `$HOME/src/team/project/shared` is allowed, but `$HOME/src` and `/` are rejected. A relative source is accepted only when it starts with `./`, such as `./shared-libs`; `../project` and `shared-libs` are rejected.

## Allowed roots

Allowed roots are read from:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/allowed-roots
```

During a normal run, the runner creates the file with the following default entry and creates `$HOME/src` if that directory does not already exist:

```text
$HOME/src
```

Each non-comment line is an absolute directory path. Entries can be edited manually to authorize a host location, for example:

```text
/home/you/src
/workspaces/team-a
/mnt/shared/customer-a
```

Every entry must already be a directory. Filesystem roots, hidden components, `.`/`..`, empty components, and symbolic-link components are rejected. An empty file disables all host directory mounts, including the starting directory.

Validation applies only to the selected source directory and the components of its path. The directory contents are not scanned or restricted: they may contain hidden files and directories, regular files, and symbolic links.

Mount destinations must be absolute, cannot be `/`, and cannot contain empty, `.`/`..`, or hidden path components. The optional mount mode is limited to `ro` or `rw`.

## Profiles

A positional profile name selects the corresponding image:

```text
rust -> pi-sandbox-rust:latest
```

If the selected image is missing, this command exits with an error. Ask an administrator to create it with `pi-sandbox-create`.
