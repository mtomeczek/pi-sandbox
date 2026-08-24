# pi-sandbox-setup

Install or remove the Unix user-local command symlinks. This command only manages setup; it does not create images or run containers.

## Usage

```text
pi-sandbox-setup --install
pi-sandbox-setup --remove
```

## Options

- `--install` — create user-local symlinks for `pi-sandbox-create`, `pi-sandbox-run`, and `pi-sandbox-setup`.
- `--remove` — remove symlinks created by `--install`.
- `-h`, `--help` — show this help.

Symlinks are stored in `${XDG_BIN_HOME:-$HOME/.local/bin}`. Installation refuses to replace regular files or unrelated symlinks, and preflights every destination before changing any of them.
