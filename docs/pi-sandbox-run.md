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
pi-sandbox-run rust --mount ~/src:/src:ro
pi-sandbox-run rust -- --help
```

## Runtime options

- `--name NAME` — sandbox instance name; changes the persistent state volume.
- `--workspace DIRECTORY` — host directory mounted as the workspace. Defaults to the current directory.
- `--container-workspace DIRECTORY` — container workspace path.
- `--mount SPEC` — add a bind mount; repeatable. Format: `HOST:CONTAINER[:OPTIONS]`.
- `--env-file FILE` — pass an environment file to Podman.
- `--state-volume NAME` — override the persistent Pi state volume.
- `--memory SIZE` — container memory limit, for example `4g`.
- `--cpus NUMBER` — CPU limit, for example `4` or `2.5`.
- `--pids-limit NUMBER` — maximum number of processes.
- `--no-network` — disable container networking and set `PI_OFFLINE=1`.
- `--shell` — start `/bin/bash` instead of Pi.
- `--image IMAGE` — override the image name.

## State and information

- `--show-state` — show persistent state-volume information.
- `--reset-state` — delete persistent Pi state after confirmation.
- `--info` — show resolved runtime configuration.
- `--dry-run` — print actions without executing them.
- `--verbose`, `--debug` — print detailed commands and diagnostics.
- `-y`, `--yes` — assume yes for confirmations.
- `-h`, `--help` — show this help.

## Profiles

A positional profile name selects the corresponding image:

```text
rust -> pi-sandbox-rust:latest
```

If the selected image is missing, this command exits with an error. Ask an administrator to create it with `pi-sandbox-create`.
