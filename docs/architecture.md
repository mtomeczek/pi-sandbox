# Script Architecture Report

This report documents the current implementation without changing it. “Cadence” means the maximum normal execution frequency within one command invocation; error-only helpers run only when their associated condition is reached.

## 1. Command map

| Public command | Platform | Private implementation | Purpose | Direct caller |
| --- | --- | --- | --- | --- |
| `pi-sandbox-create` | Bash (Linux/macOS) | same file | Create/update profile manifests, render Containerfiles, and build/remove images. | User/shell/installed symlink |
| `pi-sandbox-run` | Bash (Linux/macOS) | same file | Validate roots, workspaces, and mounts; then run an existing image. | User/shell/installed symlink |
| `pi-sandbox-setup` | Bash (Linux/macOS) | same file | Install/remove guarded user-local symlinks. | User/shell/installed symlink |
| `pi-sandbox-create.ps1` | PowerShell 7 | `scripts/windows/pi-sandbox-create.ps1` | Public forwarding wrapper for Windows creator. | User/PowerShell |
| `pi-sandbox-run.ps1` | PowerShell 7 | `scripts/windows/pi-sandbox-run.ps1` | Public forwarding wrapper for Windows runner. | User/PowerShell |

The PowerShell wrappers set strict mode, stop on errors, set UTF-8 console output, and invoke their private implementation once with `@args`. They declare no functions of their own.

## 2. End-to-end steps

### Creator flow (Bash and Windows)

1. Resolve the repository/script directory and the config, profile, template, and help paths.
2. Process `--help` immediately, or scan arguments once for `--config` so an alternate config is selected before loading defaults.
3. Load configuration; create a template-rendered default config when it is absent.
4. Parse profile and action arguments, validate names/IDs/specifications, and either load a profile manifest or write one for `--create`.
5. For `--info`, print resolved values and stop. Otherwise, verify Podman availability.
6. For `--clean-image`, optionally confirm and remove the selected image, then stop.
7. Render a Containerfile when requested or missing: validate tool/extensions, render snippets, inject APT and dynamic snippets into the base template.
8. Build only for `--update` or a missing image selected by `--build`; otherwise report that no build was requested.

### Runner flow (Bash and Windows)

1. Resolve paths and process `--config` before loading configuration.
2. Load config and allowed-root declarations. If either is missing, create it from a template. The default root is rendered as an absolute home `src` path.
3. Parse profile, runtime, mount, state, and Pi passthrough arguments.
4. Validate numeric/profile values and calculate image/state-volume names.
5. Confirm Podman availability. Information and state actions return early after their work.
6. Ensure the selected image exists unless `--dry-run` is active.
7. Resolve the workspace and every extra mount. Every source must be a strict descendant of a declared absolute allowed root; roots themselves are not mountable.
8. Create the state volume if absent, assemble hardened `podman run` arguments, forward selected API keys, then invoke Podman (or print the command in dry-run/verbose mode).

### Setup flow (Bash)

1. Accept exactly one of `--install`, `--remove`, or `--help`.
2. For install, preflight all three destination names (`create`, `run`, and `setup`) before modifying anything. Existing files are rejected unless they are symlinks resolving to this checkout.
3. Create/refresh the three symlinks and warn if the user bin directory is absent from `PATH`.
4. For removal, delete only symlinks that resolve to this checkout; foreign files and links are retained with warnings.

## 3. CLI arguments and persistent inputs

### `pi-sandbox-create`

| Argument | Value | Effect |
| --- | --- | --- |
| Positional `PROFILE` | profile name | Selects an existing profile image. |
| `--create` | profile | Writes/updates a profile manifest; implies regeneration and update. |
| `--tool` | `TOOL@VERSION` | Adds supported tool: `go`, `rust`, `jvm`, `uv`, `fnm`, or `python`. Repeatable. |
| `--extension` | `TYPE:SPEC` | Adds `uv`, `cargo`, `rustup`, or FNM Node extension. Repeatable. |
| `--npm` | `PACKAGE[@VERSION]` | Adds a global npm package. Repeatable. |
| `--env`, `--path`, `--apt` | directive value | Adds profile manifest directives. Repeatable. |
| `--build`, `--update` | none | Build if missing, or always rebuild. |
| `--regenerate-containerfile`, `--no-cache`, `--pull` | none | Regenerate or alter build behavior. `--no-cache` and `--pull` imply update. |
| `--clean-image` | none | Remove selected image after confirmation. |
| `--pi-version`, `--base-image`, `--image` | value | Override image/build metadata. |
| `--container-user`, `--container-uid`, `--container-gid` | value | Set container identity. |
| `--config` | file | Use alternate config and sibling profile/dockerfile directories. |
| `--info`, `--dry-run`, `--verbose`/`--debug`, `--yes`/`-y`, `--help`/`-h` | none | Inspection, output, confirmation, or help controls. |

### `pi-sandbox-run`

| Argument | Value | Effect |
| --- | --- | --- |
| Positional `PROFILE` | profile name | Selects `pi-sandbox-PROFILE:latest`. |
| `--name` | instance name | Names the state-volume instance. |
| `--workspace` | host directory | Selects the start directory; defaults to current directory. |
| `--mount` | `HOST:CONTAINER[:ro|rw]` | Adds a validated bind mount. Repeatable. |
| `--env-file`, `--state-volume`, `--memory`, `--cpus`, `--pids-limit` | value | Runtime settings. |
| `--no-network`, `--shell` | none | Disable networking or start Bash instead of Pi. |
| `--image` | image | Overrides image and clears selected profile. |
| `--show-state`, `--reset-state`, `--info` | none | State/config actions. |
| `--config` | file | Uses alternate config and sibling `allowed-roots` file. |
| `--dry-run`, `--verbose`/`--debug`, `--yes`/`-y`, `--help`/`-h` | none | Output, confirmation, or help controls. |
| `--` | remaining arguments | Passes all remaining arguments to Pi. |

### `pi-sandbox-setup`

| Argument | Value | Effect |
| --- | --- | --- |
| `--install` | none | Safely install all three Bash command symlinks. |
| `--remove` | none | Safely remove only owned symlinks. |
| `--help`, `-h` | none | Print setup help. |

### Persistent files and environment

| Input | Used by | Meaning |
| --- | --- | --- |
| `XDG_CONFIG_HOME` / `%APPDATA%` | Bash / Windows | Per-user config root. |
| `config` | creator and runner | Defaults and persistent overrides. |
| `allowed-roots` | runner | One absolute directory per non-comment line. |
| Profile manifest | creator and runner | Tool/image/build profile declarations. |
| Templates | creator and runner | Default config, root declarations, manifest preamble, and Containerfile snippets. |
| `XDG_BIN_HOME` | Bash setup | User-local symlink directory. |
| API-key environment variables | runner | Selected values forwarded into the container. |

## 4. Bash function inventory

### `pi-sandbox-create`

| Function and parameters | Direct callers | Cadence | Necessary? |
| --- | --- | --- | --- |
| `usage()` | help fast path; option parser | Once | Yes; Markdown is the runtime help contract. |
| `err(message...)` | validation and helpers | Error path | Yes; consistent stderr errors. |
| `log(message...)` | manifest, generation, build branches | Per action | Yes. |
| `shell_join(command...)` | `run_cmd` | Per shown command | Yes; safe readable command output. |
| `run_cmd(command...)` | `build_image`; clean action | Per Podman mutation | Yes; central dry-run/verbose behavior. |
| `trim(s)` | `load_config`; `load_manifest` | Per config/manifest line | Yes. |
| `tool_known(tool)` | profile validation; `write_containerfile` | Per tool spec | Yes. |
| `validate_npm_spec(spec)` | parser; manifest; profile; render validation | Per npm spec | Yes. |
| `render_template(template, output, replacements...)` | `write_default_config` | Once when config is absent | Yes. |
| `append_snippet(output, name, replacements...)` | `write_containerfile` | Per tool/npm/extension snippet | Yes. |
| `write_default_config()` | `load_config` | At most once | Yes. |
| `load_config()` | top-level | Once; loops config lines | Yes. |
| `validate_profile_name()` | top-level | Once | Yes. |
| `write_manifest()` | `--create` branch | Once; loops directive lists | Yes. |
| `load_manifest()` | selected-profile branch | Once; loops manifest lines | Yes. |
| `write_containerfile()` | missing/regenerate branch | Once; loops specs and template lines | Yes. |
| `require_podman()` | top-level | Once after info path | Yes. |
| `image_exists()` | build branch | Once | Yes, though clean-image bypasses it with an equivalent direct call. |
| `build_image()` | update/missing-image branch | Once | Yes. |
| `confirm()` | clean-image branch | At most once | Yes. |

### `pi-sandbox-run`

| Function and parameters | Direct callers | Cadence | Necessary? |
| --- | --- | --- | --- |
| `usage()` | help fast path; option parser | Once | Yes. |
| `err(message...)`, `warn(message...)`, `log(message...)` | helpers and action branches | Error/warning/action path | Yes. |
| `shell_join(command...)` | `run_cmd` | Per shown command | Yes. |
| `run_cmd(command...)` | reset, volume create, final run | Per Podman mutation | Yes. |
| `trim(s)` | config and root loaders | Per input line | Yes. |
| `render_template(template, output, replacements...)` | default writers | Once per absent file | Yes. |
| `write_default_config()` | `load_config` | At most once | Yes. |
| `write_default_allowed_roots()` | `load_allowed_roots` | At most once | Yes. |
| `load_allowed_roots()` | top-level | Once; loops root lines | Yes; security boundary. |
| `load_config()` | top-level | Once; loops config lines | Yes. |
| `require_podman()` | top-level | Once | Yes. |
| `confirm()` | reset-state branch | At most once | Yes. |
| `validate_host_directory(source, description)` | `resolve_workspace`; `validate_mount_spec` | Once for workspace and once per mount | Yes; security boundary. |
| `validate_container_mountpoint(target)` | `resolve_workspace`; `validate_mount_spec` | Once for workspace and once per mount | Yes. |
| `resolve_workspace()` | info and normal execution | Once | Yes. |
| `validate_mount_spec(spec)` | mount loop | Once per mount | Yes. |

### `pi-sandbox-setup`

| Function and parameters | Direct callers | Cadence | Necessary? |
| --- | --- | --- | --- |
| `err(message...)`, `warn(message...)` | validation/actions | Error/warning path | Yes. |
| `usage()` | help dispatch | Once | Yes. |
| `resolve_link_target(link)` | install; remove | Once per existing link | Yes; ownership check. |
| `validate_bin_directory()` | install; remove | Once per action | Yes. |
| `install_links()` | `--install` dispatch | Once; loops 3 commands twice | Yes; preflight prevents partial installation. |
| `remove_links()` | `--remove` dispatch | Once; loops 3 commands | Yes. |

## 5. PowerShell function inventory

### `scripts/windows/pi-sandbox-create.ps1`

| Function and parameters | Direct callers | Cadence | Necessary? |
| --- | --- | --- | --- |
| `Fail(Message)`, `Log(Message)` | helpers/actions | Error/action path | Yes. |
| `Test-Tool(Name)` | profile validation; render | Per tool spec | Yes. |
| `Test-NpmSpec(Spec)` | parser; manifest; render | Per npm spec | Yes. |
| `Show-Command(Command[])` | clean dry-run; build dry-run/verbose | Per shown action | Yes. |
| `Save-RenderedTemplate(Template, Output, Values)` | `Write-DefaultConfig` | Once if absent | Yes. |
| `Add-Snippet(Output, Name, Values)` | `Write-Containerfile` | Per generated snippet | Yes. |
| `Write-DefaultConfig()` | `Import-Config` | At most once | Yes. |
| `Get-Value(Line)` | config and manifest import | Per input line | Yes. |
| `Import-Config()` | top-level | Once; loops config lines | Yes. |
| `Write-Manifest()` | create-profile branch | Once; loops directive lists | Yes. |
| `Import-Manifest()` | selected-profile branch | Once; loops manifest lines | Yes. |
| `Write-Containerfile()` | missing/regenerate branch | Once; loops specs | Yes. |
| `Assert-Podman()` | top-level | Once | Yes. |
| `Test-Image()` | clean/build decisions | Once per decision | Yes. |
| `Confirm(Prompt)` | clean-image branch | At most once | Yes. |
| `Usage()` | help paths | Once | Yes. |

### `scripts/windows/pi-sandbox-run.ps1`

| Function and parameters | Direct callers | Cadence | Necessary? |
| --- | --- | --- | --- |
| `Fail(Message)`, `Log(Message)` | helpers/actions | Error/action path | Yes. |
| `Quote-Arg(Value)` | `Show-Command` | Once per displayed argument | Yes. |
| `Show-Command(Command[])` | dry-run/verbose actions | Per shown action | Yes. |
| `Render-Template(Template, Output, Values)` | default writers | Once per absent file | Yes. |
| `Write-DefaultConfig()`, `Write-DefaultAllowedRoots()` | loaders | At most once each | Yes. |
| `Get-ConfigValue(Line)` | `Load-Config` | Per config line | Yes. |
| `Load-Config()` | top-level | Once; loops config lines | Yes. |
| `Get-CanonicalDirectory(Path, Description)` | root loader; host validation | Per root, workspace, and mount | Yes. |
| `Test-PathBelow(Child, Parent)` | root and host validation | Per candidate root | Yes. |
| `Load-AllowedRoots()` | top-level | Once; loops root lines | Yes; security boundary. |
| `Assert-VisiblePath(Path, Description)` | host validation | Per workspace/mount | Yes. |
| `Validate-HostDirectory(Source, Description)` | workspace; mount parser | Once for workspace and per mount | Yes. |
| `Validate-ContainerMountpoint(Target)` | workspace; mount parser | Once for workspace and per mount | Yes. |
| `Resolve-Workspace()` | info and normal execution | Once | Yes. |
| `Parse-Mount(Spec)` | extra-mount loop | Once per mount | Yes. |
| `Require-Podman()` | top-level | Once | Yes. |
| `Confirm(Prompt)` | reset-state branch | At most once | Yes. |
| `Podman-Exists(Arguments[])` | volume/image/state decisions | Once per decision | Yes. |
| `Usage()` | help paths | Once | Yes. |

## 6. Necessity and duplication assessment

No uncalled functions were found. The setup command, including its self-link, is active. The only concrete local duplication is that the Bash creator’s clean-image path invokes `podman image exists` directly while `image_exists()` is used by the build path; this is consistency debt, not dead code.

The larger maintenance risk is intentional cross-platform duplication: Bash and PowerShell separately implement CLI parsing, profile/config parsing, templates, validation, and Podman invocation. Both copies remain necessary today because Windows mount/path behavior is materially different. Do not remove either implementation without replacing the platform-specific validation layer.

## 7. Alternatives to maintained shell scripts

| Option | Benefit | Cost/caveat | Recommendation |
| --- | --- | --- | --- |
| Single compiled CLI in Go, Rust, or .NET | One parser, schema, test suite, and core behavior across platforms; easy distribution as a single binary. | Requires release automation, signing/trust decisions, cross-platform builds, and explicit preservation of Windows mount semantics. | Best long-term replacement if the project needs frequent feature work. |
| Node.js/TypeScript CLI | Good argument/config libraries and alignment with Pi’s Node ecosystem. | A host Node/npm bootstrap dependency conflicts with the tool’s purpose of creating a containerized environment; bundling reintroduces release complexity. | Viable only if a bundled executable is acceptable. |
| Python CLI | Concise cross-platform filesystem and test tooling. | Adds Python/venv bootstrap and Windows distribution work. | Less attractive than compiled CLI for this tool. |
| Declarative shared schema plus existing scripts | Centralize option/config definitions and generate docs/tests while retaining platform implementations. | Does not eliminate control-flow duplication and adds generator maintenance. | Lowest-risk incremental improvement. |

There is no universally better replacement for small, dependency-free shell entrypoints. For this repository, a compiled CLI is the strongest technical option only when the value of eliminating duplicated Bash/PowerShell logic exceeds the new distribution and release burden.
