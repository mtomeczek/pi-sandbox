# Script architecture report

This report describes the shell entry points and their main execution paths. The function tables summarize the main shell helpers rather than every implementation detail. For shared Python validation, version management, and diagnostic behavior, see [sandbox management](sandbox-management.md). In the tables, “Call frequency” means the maximum normal call frequency within one command invocation; error-handling helpers run only when the relevant condition occurs.

## 1. Command map

| Public command | Platform | Private implementation | Purpose | Direct caller |
| --- | --- | --- | --- | --- |
| `pi-sandbox-create` | Bash (Linux/macOS) | same file | Create or update profile manifests, generate Containerfiles, and build or remove images. | User, shell, or installed symbolic link |
| `pi-sandbox-run` | Bash (Linux/macOS) | same file | Validate roots, workspaces, and mounts; then run an existing image. | User, shell, or installed symbolic link |
| `pi-sandbox-setup` | Bash (Linux/macOS) | same file | Install or remove validated user-local symbolic links. | User, shell, or installed symbolic link |
| `pi-sandbox-create.ps1` | PowerShell 7 | `scripts/windows/pi-sandbox-create.ps1` | Public forwarding wrapper for the Windows creator. | User or PowerShell |
| `pi-sandbox-run.ps1` | PowerShell 7 | `scripts/windows/pi-sandbox-run.ps1` | Public forwarding wrapper for the Windows runner. | User or PowerShell |

The PowerShell wrappers set strict mode, stop on errors, set UTF-8 console output, and invoke their private implementation once with `@args`. They declare no functions of their own. The creator wrapper also propagates its implementation's exit status so a failed native build cannot be reported as successful.

## 2. End-to-end steps

### Creator flow (Bash and Windows)

1. Resolve the script directory and the configuration, profile, template, and help paths.
2. Handle `--help` immediately, or inspect the arguments to select the configuration file and identify read-only actions.
3. Load global configuration. Create a default configuration file only when the selected action requires it.
4. Load the selected profile before parsing command-line overrides, so explicit options take precedence over saved values.
5. Validate the effective profile with the shared Python helper before writing a manifest or building an image.
6. Complete validation, inspection, version-audit, or profile-upgrade actions without starting an image build.
7. Verify Podman availability for image actions. List images or remove the selected image after confirmation, as requested.
8. Generate a Containerfile when requested, missing, or required by command-line changes. Reject a stale cached Containerfile before building and explain how to regenerate it.
9. Rebuild for `--update`, or build a missing image for `--build`, using an isolated context containing only `scripts/image/` helpers. Add component labels and the management tag after a successful build.

The shared Containerfile uses a Debian runtime base and copies a private Node.js runtime from a separate build stage. Image helpers run the official Pi installer against the selected release's locked manifests, keep Pi binaries outside the state volume, and provide launchers that do not change Pi's inherited project `PATH`. See [Pi installation details](sandbox-management.md#pi-installation-and-private-nodejs).

### Runner flow (Bash and Windows)

1. Resolve paths and select the configuration file before loading global settings.
2. Load configuration and allowed-root declarations. Normal runs can create defaults; dry runs and diagnostics do not create these files.
3. Parse runtime options and arguments passed to Pi, resolve the workspace, and apply its declarative `.pisandboxrc` settings. Explicit command-line profile and image choices take precedence.
4. Validate names and numeric settings, read profile environment and secret declarations, and derive image and state-volume names.
5. Complete information, state, or CLI-authentication reset actions when requested. Destructive actions require confirmation.
6. For normal startup, verify that the selected image exists. Dry runs print the requirement without querying the image.
7. Validate additional mounts, ports, and extension sources. Every bind-mount source must be a strict descendant of an allowed root; the roots themselves cannot be mounted.
8. For `--doctor`, check Podman, image metadata, secret references, and local ports without creating containers or volumes, then return.
9. Create any required Pi state volume and, if explicitly enabled, CLI-authentication volumes. Assemble the restricted `podman run` arguments and explicit environment and secret settings.
10. Install project extensions before starting the agent, stopping at the first installation failure. Start Pi or the requested shell, or print a redacted command preview for a dry run.

### Setup flow (Bash)

1. Accept exactly one of `--install`, `--remove`, or `--help`.
2. For installation, validate all three destination names (`create`, `run`, and `setup`) before modifying anything. Existing files are rejected unless they are symlinks resolving to this working tree.
3. Create or refresh the three symbolic links and warn if the user binary directory is absent from `PATH`.
4. For removal, delete only symlinks that resolve to this working tree; unrelated files and links are retained with warnings.

## 3. CLI arguments and persistent inputs

### `pi-sandbox-create`

| Argument | Value | Effect |
| --- | --- | --- |
| Positional `PROFILE` | profile name | Selects an existing profile image. |
| `--create` | profile | Creates or replaces a profile manifest; implies regeneration and update. |
| `--tool` | `TOOL@VERSION` | Adds or overrides a supported tool: `go`, `rust`, `jvm`, `uv`, `fnm`, `python`, `caddy`, or `playwright`. Repeatable. |
| `--extension` | `TYPE:SPEC` | Adds a `uv`, `cargo`, `rustup`, or FNM Node extension. Repeatable. |
| `--npm` | `PACKAGE[@VERSION]` | Adds a global npm package. Repeatable. |
| `--env`, `--path`, `--apt` | directive value | Adds profile manifest directives. Repeatable. |
| `--build`, `--update` | none | Build if missing, or always rebuild. |
| `--regenerate-containerfile`, `--no-cache`, `--pull` | none | Regenerate or alter build behavior. `--no-cache` and `--pull` imply update. |
| `--clean-image` | none | Remove selected image after confirmation. |
| `--pi-version`, `--base-image`, `--image` | value | Override image or build settings. |
| `--container-user`, `--container-uid`, `--container-gid` | value | Set container identity. |
| `--config` | file | Use an alternative configuration file and its sibling profile and Containerfile directories. |
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
| `--show-state`, `--reset-state`, `--info` | none | State/configuration actions. |
| `--config` | file | Uses an alternative configuration file and its sibling `allowed-roots` file. |
| `--dry-run`, `--verbose`/`--debug`, `--yes`/`-y`, `--help`/`-h` | none | Output, confirmation, or help controls. |
| `--` | remaining arguments | Passes all remaining arguments to Pi. |

### `pi-sandbox-setup`

| Argument | Value | Effect |
| --- | --- | --- |
| `--install` | none | Safely install all three Bash command symlinks. |
| `--remove` | none | Remove only symbolic links managed by this project. |
| `--help`, `-h` | none | Print setup help. |

### Persistent files and environment

| Input | Used by | Meaning |
| --- | --- | --- |
| `XDG_CONFIG_HOME` / `%APPDATA%` | Bash / Windows | Per-user configuration root. |
| `config` | creator and runner | Defaults and persistent overrides. |
| `allowed-roots` | runner | One absolute directory per non-comment line. |
| Profile manifest | creator and runner | Tool, image, and build declarations. |
| Templates | creator and runner | Default configuration, root declarations, manifest preamble, and Containerfile snippets. |
| `XDG_BIN_HOME` | Bash setup | User-local symlink directory. |
| API-key environment variables | runner | Selected values forwarded into the container. |

## 4. Bash function inventory

### `pi-sandbox-create`

| Function and parameters | Direct callers | Call frequency | Necessary? |
| --- | --- | --- | --- |
| `usage()` | immediate help handling; option parser | Once | Yes; Markdown is the runtime help contract. |
| `err(message...)` | validation and helpers | Error path | Yes; consistent stderr errors. |
| `log(message...)` | manifest, generation, build branches | Per action | Yes. |
| `shell_join(command...)` | `run_cmd` | Per shown command | Yes; safe readable command output. |
| `run_cmd(command...)` | `build_image`; clean action | Per Podman mutation | Yes; central dry-run/verbose behavior. |
| `trim(s)` | `load_config`; `load_manifest` | Per configuration or manifest line | Yes. |
| `tool_known(tool)` | profile validation; `write_containerfile` | Per tool specification | Yes. |
| `validate_npm_spec(spec)` | parser; manifest; profile; render validation | Per npm specification | Yes. |
| `render_template(template, output, replacements...)` | `write_default_config` | Once when configuration is absent | Yes. |
| `append_snippet(output, name, replacements...)` | `write_containerfile` | Per tool, npm, or extension snippet | Yes. |
| `write_default_config()` | `load_config` | At most once | Yes. |
| `load_config()` | top-level | Once; loops configuration lines | Yes. |
| `validate_profile_name()` | top-level | Once | Yes. |
| `write_manifest()` | `--create` branch | Once; loops directive lists | Yes. |
| `load_manifest()` | selected-profile branch | Once; loops manifest lines | Yes. |
| `write_containerfile()` | missing/regenerate branch | Once; loops specs and template lines | Yes. |
| `require_podman()` | top-level | Once after info path | Yes. |
| `image_exists()` | build branch | Once | Yes, though clean-image bypasses it with an equivalent direct call. |
| `build_image()` | update/missing-image branch | Once | Yes. |
| `confirm()` | clean-image branch | At most once | Yes. |

### `pi-sandbox-run`

| Function and parameters | Direct callers | Call frequency | Necessary? |
| --- | --- | --- | --- |
| `usage()` | immediate help handling; option parser | Once | Yes. |
| `err(message...)`, `warn(message...)`, `log(message...)` | helpers and action branches | Error, warning, or action path | Yes. |
| `shell_join(command...)` | `run_cmd` | Per shown command | Yes. |
| `run_cmd(command...)` | reset, volume create, final run | Per Podman mutation | Yes. |
| `trim(s)` | configuration and root loaders | Per input line | Yes. |
| `render_template(template, output, replacements...)` | default writers | Once per missing file | Yes. |
| `write_default_config()` | `load_config` | At most once | Yes. |
| `write_default_allowed_roots()` | `load_allowed_roots` | At most once | Yes. |
| `load_allowed_roots()` | top-level | Once; loops root lines | Yes; security boundary. |
| `load_config()` | top-level | Once; loops configuration lines | Yes. |
| `require_podman()` | top-level | Once | Yes. |
| `confirm()` | reset-state branch | At most once | Yes. |
| `validate_host_directory(source, description)` | `resolve_workspace`; `validate_mount_spec` | Once for workspace and once per mount | Yes; security boundary. |
| `validate_container_mountpoint(target)` | `resolve_workspace`; `validate_mount_spec` | Once for workspace and once per mount | Yes. |
| `resolve_workspace()` | info and normal execution | Once | Yes. |
| `validate_mount_spec(spec)` | mount loop | Once per mount | Yes. |

### `pi-sandbox-setup`

| Function and parameters | Direct callers | Call frequency | Necessary? |
| --- | --- | --- | --- |
| `err(message...)`, `warn(message...)` | validation/actions | Error or warning path | Yes. |
| `usage()` | help dispatch | Once | Yes. |
| `resolve_link_target(link)` | install; remove | Once per existing link | Yes; ownership check. |
| `validate_bin_directory()` | install; remove | Once per action | Yes. |
| `install_links()` | `--install` dispatch | Once; iterates over three commands twice | Yes; validating destinations first prevents partial installation. |
| `remove_links()` | `--remove` dispatch | Once; iterates over three commands | Yes. |

## 5. PowerShell function inventory

### `scripts/windows/pi-sandbox-create.ps1`

| Function and parameters | Direct callers | Call frequency | Necessary? |
| --- | --- | --- | --- |
| `Fail(Message)`, `Log(Message)` | helpers/actions | Error or action path | Yes. |
| `Test-Tool(Name)` | profile validation; render | Per tool specification | Yes. |
| `Test-NpmSpec(Spec)` | parser; manifest; render | Per npm specification | Yes. |
| `Show-Command(Command[])` | clean-action preview; build preview or verbose output | Per shown action | Yes. |
| `Save-RenderedTemplate(Template, Output, Values)` | `Write-DefaultConfig` | Once if absent | Yes. |
| `Add-Snippet(Output, Name, Values)` | `Write-Containerfile` | Per generated snippet | Yes. |
| `Write-DefaultConfig()` | `Import-Config` | At most once | Yes. |
| `Get-Value(Line)` | configuration and manifest import | Per input line | Yes. |
| `Import-Config()` | top-level | Once; loops configuration lines | Yes. |
| `Write-Manifest()` | create-profile branch | Once; loops directive lists | Yes. |
| `Import-Manifest()` | selected-profile branch | Once; loops manifest lines | Yes. |
| `Write-Containerfile()` | missing/regenerate branch | Once; loops specs | Yes. |
| `Assert-Podman()` | top-level | Once | Yes. |
| `Test-Image()` | clean/build decisions | Once per decision | Yes. |
| `Confirm(Prompt)` | clean-image branch | At most once | Yes. |
| `Usage()` | help paths | Once | Yes. |

### `scripts/windows/pi-sandbox-run.ps1`

| Function and parameters | Direct callers | Call frequency | Necessary? |
| --- | --- | --- | --- |
| `Fail(Message)`, `Log(Message)` | helpers/actions | Error or action path | Yes. |
| `Quote-Arg(Value)` | `Show-Command` | Once per displayed argument | Yes. |
| `Show-Command(Command[])` | dry-run/verbose actions | Per shown action | Yes. |
| `Render-Template(Template, Output, Values)` | default writers | Once per missing file | Yes. |
| `Write-DefaultConfig()`, `Write-DefaultAllowedRoots()` | loaders | At most once each | Yes. |
| `Get-ConfigValue(Line)` | `Load-Config` | Per configuration line | Yes. |
| `Load-Config()` | top-level | Once; loops configuration lines | Yes. |
| `Get-CanonicalDirectory(Path, Description)` | root loader; host validation | Per root, workspace, or mount | Yes. |
| `Test-PathBelow(Child, Parent)` | root and host validation | Per candidate root | Yes. |
| `Load-AllowedRoots()` | top-level | Once; loops root lines | Yes; security boundary. |
| `Assert-VisiblePath(Path, Description)` | host validation | Per workspace or mount | Yes. |
| `Validate-HostDirectory(Source, Description)` | workspace; mount parser | Once for workspace and per mount | Yes. |
| `Validate-ContainerMountpoint(Target)` | workspace; mount parser | Once for workspace and per mount | Yes. |
| `Resolve-Workspace()` | info and normal execution | Once | Yes. |
| `Parse-Mount(Spec)` | extra-mount loop | Once per mount | Yes. |
| `Require-Podman()` | top-level | Once | Yes. |
| `Confirm(Prompt)` | reset-state branch | At most once | Yes. |
| `Podman-Exists(Arguments[])` | volume, image, or state decisions | Once per decision | Yes. |
| `Usage()` | help paths | Once | Yes. |

## 6. Necessity and duplication assessment

The listed helpers support active command paths. The setup command also manages its own symbolic link. One local inconsistency is that the Bash creator's clean-image path invokes `podman image exists` directly, while the build path uses `image_exists()`. These paths perform the same check through different interfaces.

The main maintenance concern is intentional cross-platform duplication. Bash and PowerShell retain separate command-line parsing, configuration handling, template rendering, platform-specific path validation, and Podman invocation. Profile validation, version management, and diagnostics share a Python helper. Both shell implementations remain necessary because Windows path and mount behavior differs from Unix behavior. Any replacement must preserve the platform-specific validation rules.

## 7. Alternatives to maintained shell scripts

| Option | Benefit | Cost or limitation | Recommendation |
| --- | --- | --- | --- |
| Single compiled CLI in Go, Rust, or .NET | One parser, schema, test suite, and core behavior across platforms; distribution as a single binary. | Requires release automation, signing and trust decisions, cross-platform builds, and explicit preservation of Windows mount semantics. | Suitable as a long-term replacement if frequent feature development justifies the release requirements. |
| Node.js/TypeScript CLI | Access to argument and configuration libraries, with alignment to Pi's Node.js ecosystem. | A host dependency on Node.js and npm adds installation requirements; bundling an executable adds release complexity. | Viable only if a bundled executable is acceptable. |
| Python CLI | Concise cross-platform filesystem and test tooling. | Requires a consistent host Python installation and distribution strategy, especially on Windows. | The shared Python helper already provides some of this functionality. |
| Declarative shared schema plus existing scripts | Centralize option and configuration definitions and generate documentation and tests while retaining platform implementations. | Does not eliminate control-flow duplication and adds generator maintenance. | Lowest-risk incremental improvement. |

There is no single best replacement for small shell entry points. For this repository, a compiled CLI is appropriate only if the benefits of reducing duplicated Bash and PowerShell logic outweigh the additional distribution and release requirements.
