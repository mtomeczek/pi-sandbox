# pi-sandbox

Alias for `pi-sandbox-run`.

`pi-sandbox` is runtime-only and never dispatches to administrator/build functionality. Use `pi-sandbox-create` explicitly for image/profile administration.

Install user-local command symlinks with:

```bash
./pi-sandbox --install
```

Remove those symlinks with:

```bash
pi-sandbox --remove
```

The symlinks are stored in `${XDG_BIN_HOME:-$HOME/.local/bin}`.

For runtime usage, run:

```bash
pi-sandbox --help
```

This prints the same help as:

```bash
pi-sandbox-run --help
```
