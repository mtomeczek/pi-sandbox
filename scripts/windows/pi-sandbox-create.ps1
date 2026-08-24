#Requires -Version 7.0
<# Create and build Pi sandbox images with Windows Podman. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$ConfigRoot = if ($env:APPDATA)
{ Join-Path $env:APPDATA 'pi-sandbox'
} else
{ Join-Path $HOME 'AppData\Roaming\pi-sandbox'
}
$ConfigFile = Join-Path $ConfigRoot 'config'
$ProfilesDir = Join-Path $ConfigRoot 'profiles'
$ContainerfileDir = Join-Path $ConfigRoot 'dockerfiles'
$ContainerfileTemplate = Join-Path $ScriptDir 'templates\Containerfile.pi-sandbox.template'
$SnippetTemplate = Join-Path $ScriptDir 'templates\Containerfile.snippets.template'
$ConfigTemplate = Join-Path $ScriptDir 'templates\create.config.template'
$ProfileTemplate = Join-Path $ScriptDir 'templates\profile.template'
$HelpFile = Join-Path $ScriptDir 'docs\pi-sandbox-create.windows.md'

$Image = 'pi-sandbox:latest'; $BaseImage = 'node:24-bookworm-slim'; $PiVersion = '0.84.2'
$ContainerUser = 'pi'; $ContainerUid = '1000'; $ContainerGid = '1000'; $VerboseMode = $false
$ProfileName = ''; $ProfileFile = ''; $Containerfile = Join-Path $ContainerfileDir 'Containerfile.pi-sandbox'
$CreateProfile = $false; $Build = $false; $Update = $false; $NoCache = $false; $Pull = $false; $Regenerate = $false; $DryRun = $false; $ShowInfo = $false; $CleanImage = $false; $Yes = $false
$ToolSpecs = [Collections.Generic.List[string]]::new(); $ExtensionSpecs = [Collections.Generic.List[string]]::new(); $NpmSpecs = [Collections.Generic.List[string]]::new(); $ManifestEnvs = [Collections.Generic.List[string]]::new(); $ManifestPaths = [Collections.Generic.List[string]]::new(); $ManifestApt = [Collections.Generic.List[string]]::new()

function Fail([string]$Message)
{ throw "error: $Message"
}
function Log([string]$Message)
{ Write-Output "==> $Message"
}
function Test-Tool([string]$Name)
{ return $Name -in @('go','rust','jvm','uv','fnm','python')
}
function Test-NpmSpec([string]$Spec)
{ if ($Spec -notmatch '^(@[A-Za-z0-9][A-Za-z0-9._-]*/)?[A-Za-z0-9][A-Za-z0-9._-]*(@[A-Za-z0-9][A-Za-z0-9._+~-]*)?$')
    { Fail "invalid npm package '$Spec' (expected PACKAGE[@VERSION])"
    }
}
function Show-Command([string[]]$Command)
{ Write-Output ('+ ' + (($Command | ForEach-Object { if ($_ -match '\s')
                    { '"' + $_.Replace('"','\"') + '"'
                    } else
                    { $_
                    } }) -join ' '))
}

function Save-RenderedTemplate([string]$Template, [string]$Output, [hashtable]$Values)
{
    if (-not (Test-Path -LiteralPath $Template -PathType Leaf))
    { Fail "template not found: $Template"
    }
    $text = [IO.File]::ReadAllText($Template)
    foreach ($key in $Values.Keys)
    { $text = $text.Replace("{{$key}}", [string]$Values[$key])
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Output)) | Out-Null
    [IO.File]::WriteAllText($Output, $text)
}
function Add-Snippet([Collections.Generic.List[string]]$Output, [string]$Name, [hashtable]$Values)
{
    if (-not (Test-Path -LiteralPath $SnippetTemplate -PathType Leaf))
    { Fail "snippet template not found: $SnippetTemplate"
    }
    $lines = Get-Content -LiteralPath $SnippetTemplate
    $start = [Array]::IndexOf($lines, "@@ $Name")
    if ($start -lt 0)
    { Fail "snippet not found: $Name"
    }
    $section = [Collections.Generic.List[string]]::new()
    for ($i = $start + 1; $i -lt $lines.Count -and -not $lines[$i].StartsWith('@@ '); $i++)
    { $section.Add($lines[$i])
    }
    $text = $section -join "`n"
    foreach ($key in $Values.Keys)
    { $text = $text.Replace("{{$key}}", [string]$Values[$key])
    }
    $Output.Add($text)
}
function Write-DefaultConfig
{
    Save-RenderedTemplate $ConfigTemplate $ConfigFile @{ IMAGE=$Image; BASE_IMAGE=$BaseImage; PI_VERSION=$PiVersion; CONTAINER_USER=$ContainerUser; CONTAINER_UID=$ContainerUid; CONTAINER_GID=$ContainerGid }
}
function Get-Value([string]$Line)
{ $value = $Line.Substring($Line.IndexOf('=') + 1).Trim(); if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))
    { return $value.Substring(1,$value.Length-2)
    }; return $value
}
function Import-Config
{
    if (-not (Test-Path -LiteralPath $ConfigFile))
    { Write-DefaultConfig; return
    }
    $n = 0; foreach ($raw in Get-Content -LiteralPath $ConfigFile)
    { $n++; $line=$raw.Trim(); if (-not $line -or $line.StartsWith('#'))
        { continue
        }; if (-not $line.Contains('='))
        { Fail "${ConfigFile}:${n}: expected KEY=VALUE"
        }; $key=$line.Substring(0,$line.IndexOf('=')).Trim(); $value=Get-Value $line
        switch ($key)
        { 'IMAGE'
            {$script:Image=$value
            }; 'BASE_IMAGE'
            {$script:BaseImage=$value
            }; 'PI_VERSION'
            {$script:PiVersion=$value
            }; 'CONTAINER_USER'
            {$script:ContainerUser=$value
            }; 'CONTAINER_UID'
            {$script:ContainerUid=$value
            }; 'CONTAINER_GID'
            {$script:ContainerGid=$value
            }; 'VERBOSE'
            {if ($value -match '^(1|true|yes)$')
                {$script:VerboseMode=$true
                }
            }; 'PROFILE_DIR'
            {
            }; 'CONTAINER_HOME'
            {
            }; 'STATE_VOLUME'
            {
            }; 'AGENT_VOLUME'
            {
            }; 'MEMORY'
            {
            }; 'CPUS'
            {
            }; 'PIDS_LIMIT'
            {
            }; 'ENV_FILE'
            {
            }; 'NETWORK_MODE'
            {
            }; 'MOUNT'
            {
            }; default
            {Fail "${ConfigFile}:${n}: unsupported config key '$key'"
            }
        }
    }
}
function Write-Manifest
{
    $script:ProfileFile = Join-Path $ProfilesDir "$ProfileName.profile"
    if ($DryRun)
    { Write-Output "+ write manifest $ProfileFile"; return
    }
    if (-not (Test-Path -LiteralPath $ProfileTemplate))
    { Fail "profile manifest template not found: $ProfileTemplate"
    }
    [IO.Directory]::CreateDirectory($ProfilesDir) | Out-Null
    $lines = [Collections.Generic.List[string]]::new(); $lines.Add([IO.File]::ReadAllText($ProfileTemplate).TrimEnd()); $lines.Add(''); $lines.Add("# pi-sandbox image manifest: $ProfileName"); $lines.Add("# Generated $([DateTime]::UtcNow.ToString('o'))"); $lines.Add("PROFILE=$ProfileName"); $lines.Add("BASE_IMAGE=$BaseImage"); $lines.Add("PI_VERSION=$PiVersion")
    foreach ($x in $ToolSpecs)
    {$lines.Add("TOOL=$x")
    }; foreach ($x in $ExtensionSpecs)
    {$lines.Add("EXTENSION=$x")
    }; foreach ($x in $NpmSpecs)
    {$lines.Add("NPM=$x")
    }; foreach ($x in $ManifestEnvs)
    {$lines.Add("ENV=$x")
    }; foreach ($x in $ManifestPaths)
    {$lines.Add("PATH=$x")
    }; foreach ($x in $ManifestApt)
    {$lines.Add("APT=$x")
    }
    [IO.File]::WriteAllText($ProfileFile, ($lines -join "`n") + "`n"); Log "Wrote manifest $ProfileFile"
}
function Import-Manifest
{
    $script:ProfileFile=Join-Path $ProfilesDir "$ProfileName.profile"; if (-not (Test-Path -LiteralPath $ProfileFile))
    { Fail "profile '$ProfileName' does not exist ($ProfileFile)"
    }
    $ToolSpecs.Clear(); $ExtensionSpecs.Clear(); $NpmSpecs.Clear(); $ManifestEnvs.Clear(); $ManifestPaths.Clear(); $ManifestApt.Clear()
    foreach ($raw in Get-Content -LiteralPath $ProfileFile)
    { $line=$raw.Trim(); if (-not $line -or $line.StartsWith('#'))
        {continue
        }; if (-not $line.Contains('='))
        {Fail "${ProfileFile}: expected KEY=VALUE"
        }; $key=$line.Substring(0,$line.IndexOf('=')); $value=Get-Value $line
        switch ($key)
        { 'PROFILE'
            {
            }; 'BASE_IMAGE'
            {$script:BaseImage=$value
            }; 'PI_VERSION'
            {$script:PiVersion=$value
            }; 'PROJECT_NODE'
            {$ExtensionSpecs.Add("fnm:node@$value")
            }; 'TOOL'
            {$ToolSpecs.Add($value)
            }; 'EXTENSION'
            {$ExtensionSpecs.Add($value)
            }; 'NPM'
            {Test-NpmSpec $value; $NpmSpecs.Add($value)
            }; 'ENV'
            {$ManifestEnvs.Add($value)
            }; 'PATH'
            {$ManifestPaths.Add($value)
            }; 'APT'
            {$ManifestApt.Add($value)
            }; default
            {Fail "${ProfileFile}: unsupported key '$key'"
            }
        }
    }
    $script:Image="pi-sandbox-$ProfileName`:latest"; $script:Containerfile=Join-Path $ContainerfileDir "Containerfile.pi-sandbox.$ProfileName"
}
function Write-Containerfile
{
    Log "Generating $Containerfile"; if ($DryRun)
    {return
    }; if (-not (Test-Path -LiteralPath $ContainerfileTemplate))
    {Fail "Containerfile template not found: $ContainerfileTemplate"
    }
    $uv=''; $fnm=''; foreach ($spec in $ToolSpecs)
    {if ($spec -notmatch '@')
        {Fail "tool '$spec' must include a version"
        }; $tool,$version=$spec -split '@',2; if (-not (Test-Tool $tool))
        {Fail "unsupported tool '$tool'"
        }; if ($tool -eq 'uv')
        {$uv=$version
        }; if ($tool -eq 'fnm')
        {$fnm=$version
        }
    }
    foreach ($spec in $ExtensionSpecs)
    {switch -Wildcard ($spec)
        {'uv:*'
            {if (-not $uv)
                {Fail "extension '$spec' requires --tool uv@VERSION"
                }
            }; 'fnm:node@*'
            {if (-not $fnm -or -not $spec.Substring(9))
                {Fail "extension '$spec' requires --tool fnm@VERSION and a Node version"
                }
            }; 'cargo:*'
            {
            }; 'rustup:*'
            {
            }; default
            {Fail "unsupported extension '$spec'"
            }
        }
    }
    foreach ($spec in $NpmSpecs)
    {Test-NpmSpec $spec
    }
    $snippets=[Collections.Generic.List[string]]::new()
    foreach ($spec in $ToolSpecs)
    {$tool,$version=$spec -split '@',2; switch ($tool)
        {'go'
            {Add-Snippet $snippets go @{VERSION=$version}
            }; 'rust'
            {Add-Snippet $snippets rust @{VERSION=$version}
            }; 'jvm'
            {Add-Snippet $snippets jvm @{VERSION=$version}
            }; 'uv'
            {Add-Snippet $snippets uv @{VERSION=$version}
            }; 'python'
            {if (-not $uv)
                {Fail "python@$version requires uv"
                }; Add-Snippet $snippets python @{VERSION=$version}
            }; 'fnm'
            {Add-Snippet $snippets fnm @{VERSION=$version.TrimStart('v')}
            }
        }
    }
    if ($NpmSpecs.Count)
    {Add-Snippet $snippets 'npm-prefix' @{}; foreach ($spec in $NpmSpecs)
        {Add-Snippet $snippets 'npm-package' @{PACKAGE=$spec}
        }
    }
    foreach ($spec in $ExtensionSpecs)
    {switch -Wildcard ($spec)
        {'uv:*'
            {Add-Snippet $snippets 'extension-uv' @{PACKAGE=$spec.Substring(3)}
            }; 'cargo:*'
            {$ext=$spec.Substring(6); $crate,$v=$ext -split '@',2; $arg=if($v)
                {"--version $v"
                } else
                {''
                }; Add-Snippet $snippets 'extension-cargo' @{CRATE=$crate;VERSION_ARG=$arg}
            }; 'rustup:*'
            {Add-Snippet $snippets 'extension-rustup' @{COMPONENT=$spec.Substring(7)}
            }; 'fnm:node@*'
            {Add-Snippet $snippets 'extension-fnm-node' @{VERSION=$spec.Substring(9)}
            }
        }
    }
    foreach ($spec in $ManifestEnvs)
    {$name,$value=$spec -split '=',2; if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$')
        {Fail "invalid ENV entry '$spec'"
        }; $snippets.Add("ENV $name=`"$value`"")
    }; foreach ($spec in $ManifestPaths)
    {$snippets.Add("ENV PATH=`"$spec`${PATH}`"")
    }
    $apt=($ManifestApt | ForEach-Object { "      $_ \" }) -join "`n"; $text=[IO.File]::ReadAllText($ContainerfileTemplate).Replace('{{DYNAMIC_SNIPPETS}}',($snippets -join "`n")).Replace('{{APT_PACKAGES}}',$apt); [IO.Directory]::CreateDirectory($ContainerfileDir)|Out-Null; [IO.File]::WriteAllText($Containerfile,$text)
}
function Assert-Podman
{if (-not (Get-Command podman -ErrorAction SilentlyContinue))
    {Fail 'podman is not installed or not in PATH'
    }; if (-not $DryRun)
    {& podman info *> $null; if ($LASTEXITCODE -ne 0)
        {Fail 'podman info failed'
        }
    }
}
function Test-Image
{& podman image exists $Image *> $null; return $LASTEXITCODE -eq 0
}
function Confirm([string]$Prompt)
{if($Yes)
    {return $true
    }; return (Read-Host "$Prompt [y/N]") -match '^[Yy]([Ee][Ss])?$'
}
function Usage
{Get-Content -LiteralPath $HelpFile
}

for($i=0;$i -lt $args.Count;$i++)
{if($args[$i] -eq '--config')
    {if($i+1 -ge $args.Count)
        {Fail '--config requires FILE'
        };$ConfigFile=$args[$i+1];$ConfigRoot=Split-Path -Parent $ConfigFile;$ProfilesDir=Join-Path $ConfigRoot 'profiles';$ContainerfileDir=Join-Path $ConfigRoot 'dockerfiles';$Containerfile=Join-Path $ContainerfileDir 'Containerfile.pi-sandbox'
    }
}
if($args.Count -eq 1 -and $args[0] -in @('--help','-h'))
{Usage;exit 0
}; Import-Config
$idx=0;if($idx -lt $args.Count -and -not $args[$idx].StartsWith('-'))
{$ProfileName=$args[$idx];$idx++
}
while($idx -lt $args.Count)
{$a=$args[$idx]; switch($a)
    {'--create'
        {$idx++;if($idx -ge $args.Count)
            {Fail '--create requires PROFILE'
            };$ProfileName=$args[$idx];$CreateProfile=$true
        };'--tool'
        {$idx++;$ToolSpecs.Add($args[$idx])
        };'--extension'
        {$idx++;$ExtensionSpecs.Add($args[$idx])
        };'--npm'
        {$idx++;Test-NpmSpec $args[$idx];$NpmSpecs.Add($args[$idx])
        };'--project-node'
        {$idx++;$ExtensionSpecs.Add("fnm:node@$($args[$idx])")
        };'--env'
        {$idx++;$ManifestEnvs.Add($args[$idx])
        };'--path'
        {$idx++;$ManifestPaths.Add($args[$idx])
        };'--apt'
        {$idx++;$ManifestApt.Add($args[$idx])
        };'--build'
        {$Build=$true
        };'--update'
        {$Update=$true
        };'--regenerate-containerfile'
        {$Regenerate=$true
        };'--no-cache'
        {$NoCache=$true;$Update=$true
        };'--pull'
        {$Pull=$true;$Update=$true
        };'--clean-image'
        {$CleanImage=$true
        };'--pi-version'
        {$idx++;$PiVersion=$args[$idx]
        };'--base-image'
        {$idx++;$BaseImage=$args[$idx]
        };'--image'
        {$idx++;$Image=$args[$idx]
        };'--container-user'
        {$idx++;$ContainerUser=$args[$idx]
        };'--container-uid'
        {$idx++;$ContainerUid=$args[$idx]
        };'--container-gid'
        {$idx++;$ContainerGid=$args[$idx]
        };'--config'
        {$idx++
        };'--info'
        {$ShowInfo=$true
        };'--dry-run'
        {$DryRun=$true
        };'--verbose'
        {$VerboseMode=$true
        };'--debug'
        {$VerboseMode=$true
        };'--yes'
        {$Yes=$true
        };'-y'
        {$Yes=$true
        };'--help'
        {Usage;exit 0
        };'-h'
        {Usage;exit 0
        };default
        {Fail "unknown option: $a"
        }
    };$idx++
}
if($ProfileName -and $ProfileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$')
{Fail "invalid profile name '$ProfileName'"
}; if($ContainerUid -notmatch '^\d+$' -or $ContainerGid -notmatch '^\d+$')
{Fail 'container UID and GID must be numeric'
}
if($CreateProfile)
{if(-not $ProfileName)
    {Fail '--create requires a profile'
    };if(-not $ToolSpecs.Count)
    {Fail 'profile creation requires at least one --tool TOOL@VERSION'
    };foreach($spec in $ToolSpecs)
    {$tool=$spec.Split('@')[0];if(-not(Test-Tool $tool))
        {Fail "unsupported tool '$tool'"
        }
    };$Image="pi-sandbox-$ProfileName`:latest";$Containerfile=Join-Path $ContainerfileDir "Containerfile.pi-sandbox.$ProfileName";Write-Manifest;$Regenerate=$true;$Update=$true
} elseif($ProfileName)
{Import-Manifest
}
if($ShowInfo)
{Write-Output "pi-sandbox build configuration";Write-Output "  profile:       $(if($ProfileName){$ProfileName}else{'default'})";Write-Output "  manifest:      $(if($ProfileFile){$ProfileFile}else{'none'})";Write-Output "  image:         $Image";Write-Output "  containerfile: $Containerfile";Write-Output "  base image:    $BaseImage";Write-Output "  Pi version:    $PiVersion";Write-Output "  tools:         $($ToolSpecs -join ' ')";Write-Output "  extensions:    $($ExtensionSpecs -join ' ')";exit 0
}
Assert-Podman
if($CleanImage)
{if($DryRun)
    {Show-Command @('podman','image','rm',$Image)
    } elseif(Test-Image)
    {if(-not(Confirm "Remove image '$Image'?"))
        {exit 1
        };& podman image rm $Image
    } else
    {Write-Output "Image '$Image' does not exist."
    };exit 0
}
if($Regenerate -or -not(Test-Path -LiteralPath $Containerfile))
{Write-Containerfile
}
if($Update -or $Build)
{$shouldBuild=$Update -or -not(Test-Image);if($shouldBuild)
    {Log "Building $Image";$buildArgs=[Collections.Generic.List[string]]::new();$buildArgs.AddRange([string[]]@('build','--tag',$Image,'--build-arg',"BASE_IMAGE=$BaseImage",'--build-arg',"PI_VERSION=$PiVersion",'--build-arg',"USER_NAME=$ContainerUser",'--build-arg',"USER_UID=$ContainerUid",'--build-arg',"USER_GID=$ContainerGid",'--file',$Containerfile));if($NoCache)
        {$buildArgs.Add('--no-cache')
        };if($Pull)
        {$buildArgs.Add('--pull=always')
        };$buildArgs.Add((New-TemporaryFile).DirectoryName);if($DryRun -or $VerboseMode)
        {Show-Command (@('podman')+$buildArgs.ToArray())
        };if(-not$DryRun)
        {& podman @buildArgs;exit $LASTEXITCODE
        }
    } else
    {Log "Image already exists: $Image"
    }
} else
{Log 'No build requested. Use --build or --update.'
}
