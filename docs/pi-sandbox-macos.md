# macOS support

`pi-sandbox-create`, `pi-sandbox-run`, and `pi-sandbox-setup` are the macOS command scripts. They do not need PowerShell wrappers or a GNU coreutils installation: the scripts support macOS's bundled Bash 3.2 and BSD utilities.

## Requirements

- Podman Desktop or Podman with a running machine
- Bash (the macOS-provided `/bin/bash` is supported)
- Network access while building images

Initialize and start the Podman machine when needed:

```bash
podman machine init   # first use only
podman machine start
```

## Install commands

Install the commands into the XDG-style user bin directory:

```bash
./pi-sandbox-setup --install
```

On macOS the default destination is `~/.local/bin`. Add it to `PATH` if it is not already present:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

The installer only creates or removes symlinks that point to this checkout. Remove them with:

```bash
pi-sandbox-setup --remove
```

## Configuration and usage

Configuration follows the Unix XDG locations, using `~/.config` by default:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/config
${XDG_CONFIG_HOME:-$HOME/.config}/pi-sandbox/allowed-roots
```

Create and run profiles exactly as on other Unix hosts:

```bash
./pi-sandbox-create --create rust --tool rust@1.90.0
./pi-sandbox-run rust
```

See [creator usage](pi-sandbox-create.md), [runner usage](pi-sandbox-run.md), and [setup usage](pi-sandbox-setup.md) for the full option references.

## Validation

Run the macOS portability regression from the repository root:

```bash
bash tests/macos-compat.sh
```

It checks script syntax, rejects GNU-only path-utility invocations, and verifies that all commands can locate their documentation when invoked through symlinks.
