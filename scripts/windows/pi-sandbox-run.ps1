#Requires -Version 7.0
<##
Run existing Pi sandbox images with Windows Podman.
Configuration is stored in %APPDATA%\pi-sandbox (the Windows equivalent of the
Unix XDG configuration location), unless --config selects another file.
##>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$ConfigRoot = if ($env:APPDATA)
{ Join-Path $env:APPDATA 'pi-sandbox'
} else
{ Join-Path $HOME 'AppData\Roaming\pi-sandbox'
}
$ConfigFile = Join-Path $ConfigRoot 'config'
$AllowedRootsFile = Join-Path $ConfigRoot 'allowed-roots'
$ConfigTemplate = Join-Path $ScriptDir 'templates\run.config.template'
$AllowedRootsTemplate = Join-Path $ScriptDir 'templates\allowed-roots.template'

$Image = 'pi-sandbox:latest'
$ContainerUser = 'pi'
$ContainerUid = '1000'
$ContainerGid = '1000'
$ContainerHome = '/home/pi'
$AgentVolume = 'pi-agent'
$Memory = ''
$Cpus = ''
$PidsLimit = '512'
$EnvFile = ''
$NetworkMode = 'default'
$VerboseMode = $false

$InstanceName = ''
$HostWorkspace = ''
$ShellMode = $false
$DryRun = $false
$ShowInfo = $false
$ShowState = $false
$ResetState = $false
$Yes = $false
$StateVolumeSet = $false
$ExtraMounts = [System.Collections.Generic.List[string]]::new()
$ProfileName = ''
$PiArgs = [System.Collections.Generic.List[string]]::new()
$AllowedRoots = [System.Collections.Generic.List[string]]::new()

function Fail([string]$Message)
{ throw "error: $Message"
}
function Log([string]$Message)
{ Write-Host "==> $Message"
}
function Quote-Arg([string]$Value)
{ if ($Value -match '[\s"'']')
    { return '"' + $Value.Replace('"', '\"') + '"'
    }; return $Value
}
function Show-Command([string[]]$Command)
{ Write-Host ('+ ' + (($Command | ForEach-Object { Quote-Arg $_ }) -join ' '))
}

function Render-Template([string]$Template, [string]$Output, [hashtable]$Values)
{
    if (-not (Test-Path -LiteralPath $Template -PathType Leaf))
    { Fail "template not found: $Template"
    }
    $content = [System.IO.File]::ReadAllText($Template)
    foreach ($key in $Values.Keys)
    { $content = $content.Replace("{{$key}}", [string]$Values[$key])
    }
    $directory = Split-Path -Parent $Output
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    [System.IO.File]::WriteAllText($Output, $content)
}

function Write-DefaultConfig
{
    Render-Template $ConfigTemplate $ConfigFile @{
        CONTAINER_USER = $ContainerUser; CONTAINER_UID = $ContainerUid; CONTAINER_GID = $ContainerGid
        CONTAINER_HOME = $ContainerHome; STATE_VOLUME = $AgentVolume; MEMORY = $Memory; CPUS = $Cpus
        PIDS_LIMIT = $PidsLimit; ENV_FILE = $EnvFile; NETWORK_MODE = $NetworkMode; VERBOSE = '0'
    }
}

function Write-DefaultAllowedRoots
{
    $defaultRoot = Join-Path $HOME 'src'
    if (-not (Test-Path -LiteralPath $defaultRoot))
    { [System.IO.Directory]::CreateDirectory($defaultRoot) | Out-Null
    }
    if (-not (Test-Path -LiteralPath $defaultRoot -PathType Container))
    { Fail "default allowed root is not a directory: $defaultRoot"
    }
    if (-not (Test-Path -LiteralPath $AllowedRootsTemplate -PathType Leaf))
    { Fail "template not found: $AllowedRootsTemplate"
    }
    Render-Template $AllowedRootsTemplate $AllowedRootsFile @{ DEFAULT_ROOT = $defaultRoot }
}

function Get-ConfigValue([string]$Line)
{
    $value = $Line.Substring($Line.IndexOf('=') + 1).Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))
    { return $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Load-Config
{
    if (-not (Test-Path -LiteralPath $ConfigFile))
    { Write-DefaultConfig; return
    }
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $ConfigFile)
    {
        $lineNumber++; $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#'))
        { continue
        }
        if (-not $line.Contains('='))
        { Fail "${ConfigFile}:${lineNumber}: expected KEY=VALUE"
        }
        $key = $line.Substring(0, $line.IndexOf('=')).Trim(); $value = Get-ConfigValue $line
        switch ($key)
        {
            'IMAGE'
            { $script:Image = $value
            }
            'CONTAINER_USER'
            { $script:ContainerUser = $value
            }
            'CONTAINER_UID'
            { $script:ContainerUid = $value
            }
            'CONTAINER_GID'
            { $script:ContainerGid = $value
            }
            'CONTAINER_HOME'
            { $script:ContainerHome = $value
            }
            'STATE_VOLUME'
            { $script:AgentVolume = $value
            }
            'AGENT_VOLUME'
            { $script:AgentVolume = $value
            }
            'MEMORY'
            { $script:Memory = $value
            }
            'CPUS'
            { $script:Cpus = $value
            }
            'PIDS_LIMIT'
            { $script:PidsLimit = $value
            }
            'ENV_FILE'
            { $script:EnvFile = $value
            }
            'NETWORK_MODE'
            { $script:NetworkMode = $value
            }
            'MOUNT'
            { $script:ExtraMounts.Add($value)
            }
            'VERBOSE'
            { if ($value -match '^(1|true|yes)$')
                { $script:VerboseMode = $true
                }
            }
            'BASE_IMAGE'
            {
            }
            'PI_VERSION'
            {
            }
            'PROFILE_DIR'
            {
            }
            default
            { Fail "${ConfigFile}:${lineNumber}: unsupported config key '$key'"
            }
        }
    }
}

function Get-CanonicalDirectory([string]$Path, [string]$Description)
{
    if (-not (Test-Path -LiteralPath $Path -PathType Container))
    { Fail "$Description must be an existing directory: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    { Fail "$Description cannot be a symbolic link or junction: $Path"
    }
    return [IO.Path]::GetFullPath($item.FullName).TrimEnd('\', '/')
}

function Test-PathBelow([string]$Child, [string]$Parent)
{
    $prefix = $Parent.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $Child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Load-AllowedRoots
{
    if (-not (Test-Path -LiteralPath $AllowedRootsFile))
    { Write-DefaultAllowedRoots
    }
    $script:AllowedRoots.Clear()
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $AllowedRootsFile)
    {
        $lineNumber++; $entry = $rawLine.Trim()
        if (-not $entry -or $entry.StartsWith('#'))
        { continue
        }
        if (-not [IO.Path]::IsPathRooted($entry) -or $entry -match '(^|[\\/])\.{1,2}([\\/]|$)' -or $entry -match '(^|[\\/])\.')
        { Fail "${AllowedRootsFile}:${lineNumber}: allowed root must be a visible absolute path: $entry"
        }
        $candidate = Get-CanonicalDirectory $entry 'allowed root'
        $rootPath = [IO.Path]::GetPathRoot($candidate).TrimEnd('\', '/')
        if ($candidate.TrimEnd('\', '/') -eq $rootPath)
        { Fail "${AllowedRootsFile}:${lineNumber}: filesystem root is not an allowed root: $entry"
        }
        if (-not ($script:AllowedRoots | Where-Object { $_.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) }))
        { $script:AllowedRoots.Add($candidate)
        }
    }
}

function Assert-VisiblePath([string]$Path, [string]$Description)
{
    foreach ($part in ($Path -split '[\\/]'))
    { if ($part.StartsWith('.'))
        { Fail "$Description contains a hidden path component: $Path"
        }
    }
}

function Validate-HostDirectory([string]$Source, [string]$Description)
{
    if ($Source.StartsWith('.\') -or $Source.StartsWith('./'))
    { $Source = Join-Path (Get-Location) $Source.Substring(2)
    } elseif (-not [IO.Path]::IsPathRooted($Source))
    { Fail "$Description must be an absolute path or start with '.\': $Source"
    }
    if ($Source -match '(^|[\\/])\.{1,2}([\\/]|$)')
    { Fail "$Description cannot contain '.' or '..': $Source"
    }
    Assert-VisiblePath $Source $Description
    $canonical = Get-CanonicalDirectory $Source $Description
    foreach ($root in $AllowedRoots)
    { if (Test-PathBelow $canonical $root)
        { return $canonical
        }
    }
    $roots = if ($AllowedRoots.Count)
    { $AllowedRoots -join ', '
    } else
    { 'none configured'
    }
    Fail "$Description must be below an allowed root ($roots): $canonical"
}

function Validate-ContainerMountpoint([string]$Target)
{
    if (-not $Target.StartsWith('/') -or $Target -eq '/' -or $Target -match '//' -or $Target -match '(^|/)\.{1,2}(/|$)' -or $Target -match '(^|)/\.')
    { Fail "invalid container mount destination: $Target"
    }
}

function Resolve-Workspace
{
    if (-not $HostWorkspace)
    { $script:HostWorkspace = (Get-Location).Path
    }
    $script:HostWorkspace = Validate-HostDirectory $HostWorkspace 'workspace'
    $name = Split-Path -Leaf $HostWorkspace
    $script:ContainerStartDir = "$($ContainerHome.TrimEnd('/'))/$name"
    Validate-ContainerMountpoint $ContainerStartDir
}

function Parse-Mount([string]$Spec)
{
    if ($Spec -notmatch '^(?<source>[A-Za-z]:[\\/].*):(?<target>/[^:]+)(:(?<mode>ro|rw))?$')
    { Fail "invalid --mount '$Spec'; expected C:\host:/container[:ro|rw]"
    }
    $source = Validate-HostDirectory $Matches.source 'mount source'
    Validate-ContainerMountpoint $Matches.target
    $mode = if ($Matches.mode)
    { $Matches.mode
    } else
    { 'rw'
    }
    return "$source`:$($Matches.target):$mode"
}

function Require-Podman
{
    if (-not (Get-Command podman -ErrorAction SilentlyContinue))
    { Fail 'podman is not installed or not in PATH'
    }
    if (-not $DryRun)
    { & podman info *> $null; if ($LASTEXITCODE -ne 0)
        { Fail 'podman info failed'
        }
    }
}

function Confirm([string]$Prompt)
{ if ($Yes)
    { return $true
    }; return (Read-Host "$Prompt [y/N]") -match '^[Yy]([Ee][Ss])?$'
}
function Podman-Exists([string[]]$Arguments)
{ & podman @Arguments *> $null; return $LASTEXITCODE -eq 0
}

function Usage
{ Get-Content -LiteralPath (Join-Path $ScriptDir 'docs\pi-sandbox-run.windows.md')
}

# Select an alternate config before loading defaults.
for ($i = 0; $i -lt $args.Count; $i++)
{ if ($args[$i] -eq '--config')
    { if ($i + 1 -ge $args.Count)
        { Fail '--config requires FILE'
        }; $ConfigFile = $args[$i + 1]; $ConfigRoot = Split-Path -Parent $ConfigFile; $AllowedRootsFile = Join-Path $ConfigRoot 'allowed-roots'
    }
}
if ($args.Count -eq 1 -and $args[0] -in @('--help', '-h'))
{ Usage; exit 0
}

Load-Config
Load-AllowedRoots

$index = 0
if ($index -lt $args.Count -and -not $args[$index].StartsWith('-'))
{ $ProfileName = $args[$index]; $index++
}
while ($index -lt $args.Count)
{
    $argument = $args[$index]
    if ($argument -eq '--')
    { $index++; while ($index -lt $args.Count)
        { $PiArgs.Add($args[$index]); $index++
        }; break
    }
    switch ($argument)
    {
        '--name'
        { $index++; if ($index -ge $args.Count)
            { Fail '--name requires NAME'
            }; $InstanceName = $args[$index]
        }
        '--workspace'
        { $index++; if ($index -ge $args.Count)
            { Fail '--workspace requires DIRECTORY'
            }; $HostWorkspace = $args[$index]
        }
        '--mount'
        { $index++; if ($index -ge $args.Count)
            { Fail '--mount requires SPEC'
            }; $ExtraMounts.Add($args[$index])
        }
        '--env-file'
        { $index++; if ($index -ge $args.Count)
            { Fail '--env-file requires FILE'
            }; $EnvFile = $args[$index]
        }
        '--state-volume'
        { $index++; if ($index -ge $args.Count)
            { Fail '--state-volume requires NAME'
            }; $AgentVolume = $args[$index]; $StateVolumeSet = $true
        }
        '--memory'
        { $index++; if ($index -ge $args.Count)
            { Fail '--memory requires SIZE'
            }; $Memory = $args[$index]
        }
        '--cpus'
        { $index++; if ($index -ge $args.Count)
            { Fail '--cpus requires NUMBER'
            }; $Cpus = $args[$index]
        }
        '--pids-limit'
        { $index++; if ($index -ge $args.Count)
            { Fail '--pids-limit requires NUMBER'
            }; $PidsLimit = $args[$index]
        }
        '--no-network'
        { $NetworkMode = 'none'
        }
        '--shell'
        { $ShellMode = $true
        }
        '--image'
        { $index++; if ($index -ge $args.Count)
            { Fail '--image requires IMAGE'
            }; $Image = $args[$index]; $ProfileName = ''
        }
        '--show-state'
        { $ShowState = $true
        }
        '--reset-state'
        { $ResetState = $true
        }
        '--info'
        { $ShowInfo = $true
        }
        '--dry-run'
        { $DryRun = $true
        }
        '--verbose'
        { $VerboseMode = $true
        }
        '--debug'
        { $VerboseMode = $true
        }
        '--yes'
        { $Yes = $true
        }
        '-y'
        { $Yes = $true
        }
        '--config'
        { $index++
        }
        '--help'
        { Usage; exit 0
        }
        '-h'
        { Usage; exit 0
        }
        default
        { Fail "unknown option: $argument"
        }
    }
    $index++
}

if ($ProfileName -and $ProfileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
{ Fail "invalid profile name '$ProfileName'"
}
if ($InstanceName -and $InstanceName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
{ Fail "invalid sandbox name '$InstanceName'"
}
if ($PidsLimit -notmatch '^\d+$')
{ Fail 'pids limit must be numeric'
}
if (-not $ContainerHome.StartsWith('/'))
{ Fail 'container home must be an absolute path'
}

if ($ProfileName)
{ $Image = "pi-sandbox-$ProfileName`:latest"; if (-not $StateVolumeSet)
    { $AgentVolume = "pi-agent-$ProfileName$(if ($InstanceName) { "-$InstanceName" })"
    }
} elseif ($AgentVolume -eq 'pi-agent' -and $InstanceName -and -not $StateVolumeSet)
{ $AgentVolume = "pi-agent-$InstanceName"
}

Require-Podman
if ($ShowInfo)
{
    Resolve-Workspace
    Write-Output "pi-sandbox runtime configuration"
    Write-Output "  profile:             $(if ($ProfileName) { $ProfileName } else { 'default' })"
    Write-Output "  image:               $Image"
    Write-Output "  container user:      $ContainerUser ($ContainerUid`:$ContainerGid)"
    Write-Output "  container start dir: $ContainerStartDir"
    Write-Output "  host start dir:      $HostWorkspace"
    Write-Output "  state volume:        $AgentVolume"
    Write-Output "  network:             $NetworkMode"
    Write-Output "  allowed-roots file:  $AllowedRootsFile"
    Write-Output "  allowed roots:       $(if ($AllowedRoots.Count) { $AllowedRoots -join ', ' } else { 'none configured' })"
    exit 0
}
if ($ShowState)
{ if ($DryRun)
    { Show-Command ([string[]]@('podman', 'volume', 'inspect', $AgentVolume))
    } elseif (Podman-Exists ([string[]]@('volume', 'exists', $AgentVolume)))
    { & podman volume inspect $AgentVolume
    } else
    { Write-Output "State volume '$AgentVolume' does not exist."
    }; exit 0
}
if ($ResetState)
{ if ($DryRun)
    { Show-Command ([string[]]@('podman', 'volume', 'rm', $AgentVolume))
    } elseif (Podman-Exists ([string[]]@('volume', 'exists', $AgentVolume)))
    { if (-not (Confirm "Remove Pi state volume '$AgentVolume'? This deletes saved state."))
        { exit 1
        }; & podman volume rm $AgentVolume | Out-Null; Write-Output "Removed state volume '$AgentVolume'."
    } else
    { Write-Output "State volume '$AgentVolume' does not exist."
    }; exit 0
}

if ($DryRun)
{ Write-Output "# Require existing image: $Image"
} elseif (-not (Podman-Exists ([string[]]@('image', 'exists', $Image))))
{ Fail "sandbox image '$Image' does not exist; ask an administrator to create it"
}
Resolve-Workspace
$validatedMounts = foreach ($mount in $ExtraMounts)
{ Parse-Mount $mount
}
if (-not $DryRun -and -not (Podman-Exists ([string[]]@('volume', 'exists', $AgentVolume))))
{ Log "Creating Pi state volume: $AgentVolume"; & podman volume create $AgentVolume | Out-Null
}

$runArgs = [System.Collections.Generic.List[string]]::new()
$runArgs.AddRange([string[]]@('run', '--rm', '--interactive', '--tty', "--userns=keep-id:uid=$ContainerUid,gid=$ContainerGid", '--cap-drop=ALL', '--security-opt=no-new-privileges', "--pids-limit=$PidsLimit", '--env', "HOME=$ContainerHome", '--env', "USER=$ContainerUser", '--env', "XDG_CONFIG_HOME=$ContainerHome/.config", '--env', "XDG_DATA_HOME=$ContainerHome/.local/share", '--env', "XDG_CACHE_HOME=$ContainerHome/.cache", '--env', "XDG_STATE_HOME=$ContainerHome/.local/state", '--env', "XDG_BIN_HOME=$ContainerHome/.local/bin", '--volume', "$HostWorkspace`:$ContainerStartDir`:rw", '--volume', "$AgentVolume`:$ContainerHome/.pi/agent:rw", '--workdir', $ContainerStartDir))
if ($Memory)
{ $runArgs.Add('--memory'); $runArgs.Add($Memory)
}
if ($Cpus)
{ $runArgs.Add('--cpus'); $runArgs.Add($Cpus)
}
if ($NetworkMode -eq 'none')
{ $runArgs.Add('--network=none'); $runArgs.Add('--env'); $runArgs.Add('PI_OFFLINE=1')
}
foreach ($mount in $validatedMounts)
{ $runArgs.Add('--volume'); $runArgs.Add($mount)
}
if ($EnvFile)
{ if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf))
    { Fail "environment file is not readable: $EnvFile"
    }; $runArgs.Add('--env-file'); $runArgs.Add($EnvFile)
}
foreach ($name in @('ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_API_KEY', 'GOOGLE_API_KEY'))
{ if ([Environment]::GetEnvironmentVariable($name))
    { $runArgs.Add('--env'); $runArgs.Add($name)
    }
}
$runArgs.Add($Image)
if ($ShellMode)
{ $runArgs.AddRange([string[]]@('--entrypoint', '/bin/bash'))
}
foreach ($value in $PiArgs)
{ $runArgs.Add($value)
}
Log 'Starting Pi sandbox'; Write-Output "    image:     $Image"; Write-Output "    start dir:  $HostWorkspace -> $ContainerStartDir"; Write-Output "    state:     $AgentVolume"; Write-Output "    network:   $NetworkMode"
if ($DryRun -or $VerboseMode)
{ Show-Command (@('podman') + $runArgs.ToArray())
}
if (-not $DryRun)
{ & podman @runArgs; exit $LASTEXITCODE
}
