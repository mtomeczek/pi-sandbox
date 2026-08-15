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
pi-sandbox-run rust -- --help
```

## Runtime options

- `--name NAME` — sandbox instance name; changes the persistent state volume.
- `--workspace DIRECTORY` — host directory mounted as the workspace. Defaults to the current directory. It must satisfy the host-directory restrictions below.
- `--container-workspace DIRECTORY` — container workspace path.
- `--mount SPEC` — add a bind mount; repeatable. Format: `HOST:CONTAINER[:ro|rw]`. Both paths are validated as described below.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
- `--memory SIZE` — container memory limit, for example `4g`.
- `--cpus NUMBER` — CPU limit, for example `4` or `2.5`.
- `--pids-limit NUMBER` — maximum number of processes.
- `--no-network` — disable container networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.

## User installation

- `--install` — create user-local symlinks for `pi-sandbox`, `pi-sandbox-run`, and `pi-sandbox-create`.
- `--remove` — remove user-local symlinks created by `--install`.

Symlinks are stored in `${XDG_BIN_HOME:-$HOME/.local/bin}`. Installation refuses
to replace regular files or unrelated symlinks.

## State and information

- `--show-state` — show persistent state-volume information.
- `--reset-state` — delete persistent Pi state after confirmation.
- `--info` — show resolved runtime configuration.
- `--dry-run` — print actions without executing them.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## Bind-mount restrictions

The workspace and every extra bind-mount source must:

- be an existing directory, not a file;
- be a strict subdirectory of `$HOME/SAPDevelop` or `$HOME/src`;
- use an absolute path or start with `./`; `./` paths are expanded from the current directory before all other checks;
- resolve to a canonical path;
- contain no symbolic-link components;
- contain no `.` or `..` traversal components;
- contain no hidden directory component whose name starts with `.`.

The source may be nested at any depth below an approved root; it does not need
to be a direct child. The approved roots themselves cannot be mounted. For
example, `$HOME/src/team/project/shared` is allowed, but `$HOME/src`, `$HOME`,
and `/` are rejected. A relative source is accepted only when it starts with
`./`, such as `./shared-libs`; `../project` and `shared-libs` are rejected.

Validation applies only to the selected source directory and the components of
its path. The directory contents are not scanned or restricted: they may contain
hidden files/directories, regular files, and symbolic links.

Mount destinations must be absolute, cannot be `/`, and cannot contain empty,
`.`/`..`, or hidden path components. Optional mount mode is limited to `ro` or
`rw`.

## Profiles

A positional profile name selects the corresponding image:

```text
rust -> pi-sandbox-rust:latest
```

If the selected image is missing, this command exits with an error. Ask an administrator to create it with `pi-sandbox-create`.
