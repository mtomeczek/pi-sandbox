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
- `--workspace DIRECTORY` — host directory mounted as the starting directory. Defaults to the current directory. It must satisfy the host-directory restrictions below. Inside the container it is mounted under `$CONTAINER_HOME` with the same basename.
- `--mount SPEC` — add a bind mount; repeatable. Format: `HOST:CONTAINER[:ro|rw]`. Both paths are validated as described below.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
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
- `--dry-run` — print actions without executing them.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## Starting directory

The selected host directory keeps its name inside the container. For example:

```text
$HOME/src/team/backend -> /home/pi/backend
```

Pi starts in `/home/pi/backend`, not in a generic `workspace` directory. The
same rule applies when the starting directory is selected with `--workspace`.

## Bind-mount restrictions

The starting directory and every extra bind-mount source are validated in the
same way. Each source must:

- be an existing directory, not a file;
- be a strict subdirectory of a root listed in the `allowed-roots` file;
- use an absolute path or start with `./`; `./` paths are expanded from the current directory before all other checks;
- resolve to a canonical path;
- contain no symbolic-link components;
- contain no `.` or `..` traversal components;
- contain no hidden directory component whose name starts with `.`.

The source may be nested at any depth below an approved root; it does not need
to be a direct child. The approved roots themselves cannot be mounted. For
example, with the default `$HOME/src` root, `$HOME/src/team/project/shared` is
allowed, but `$HOME/src` and `/` are rejected. A relative source is
accepted only when it starts with `./`, such as `./shared-libs`; `../project`
and `shared-libs` are rejected.

## Allowed roots

Allowed roots are read from:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/allowed-roots
```

The file is created automatically with this default entry, and `$HOME/src` is
created if it does not already exist:

```text
$HOME/src
```

Each non-comment line is an absolute directory path. Entries can be edited by
hand to authorize any host location, for example:

```text
/home/you/src
/workspaces/team-a
/mnt/shared/customer-a
```

Every entry must already be a directory. Filesystem roots, hidden components,
`.`/`..`, empty components, and symbolic-link components are rejected. An empty
file disables all host directory mounts, including the starting directory.

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
