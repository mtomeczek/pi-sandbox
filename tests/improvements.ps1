#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('sandbox-improvements-' + [guid]::NewGuid())
$oldPath = $env:PATH; $oldLog = $env:PODMAN_LOG
function Invoke-TestCommand([string]$Script, [string[]]$Arguments, [int]$Expected = 0) {
    $output = @(& pwsh -NoProfile -File $Script @Arguments 2>&1) -join "`n"
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected command result: $output" }
    return $output
}
try {
    $configDir = Join-Path $work 'config'
    $project = Join-Path $work 'allowed/project'
    $bin = Join-Path $work 'bin'
    New-Item -ItemType Directory $project, $bin, "$configDir/profiles" | Out-Null
    $config = Join-Path $configDir 'config'
    [IO.File]::WriteAllText($config, '')
    [IO.File]::WriteAllText((Join-Path $configDir 'allowed-roots'), (Join-Path $work 'allowed') + "`n")
    [IO.File]::WriteAllText((Join-Path $configDir 'profiles/demo.profile'), "PROFILE=demo`nBASE_IMAGE=node:24-bookworm-slim`nPI_VERSION=1.0.0`nTOOL=go@1.26.0`nENV_SECRET=API_TOKEN=api-token`n")
    [IO.File]::WriteAllText((Join-Path $bin 'podman.ps1'), 'Add-Content -LiteralPath $env:PODMAN_LOG -Value ($args -join " "); exit 0')
    $nativeStub = @'
@echo off
echo %*>>"%PODMAN_LOG%"
if "%1"=="info" echo {"host":{"security":{"rootless":true}}}
if "%1 %2"=="image inspect" echo [{"Config":{"Labels":{"io.pi-sandbox.template-version":"2","io.pi-sandbox.capabilities":"glab-device"}}}]
exit /b 0
'@
    [IO.File]::WriteAllText((Join-Path $bin 'podman.cmd'), $nativeStub)
    $env:PODMAN_LOG = Join-Path $work 'podman.log'
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    $creator = Join-Path $root 'scripts/windows/pi-sandbox-create.ps1'
    $runner = Join-Path $root 'scripts/windows/pi-sandbox-run.ps1'
    $output = Invoke-TestCommand $creator @('demo', '--config', $config, '--pi-version', '1.4.0', '--tool', 'go@1.27.3', '--image', 'manual:tag', '--info')
    foreach ($expected in @('1.4.0', 'go@1.27.3', 'manual:tag')) {
        if (-not $output.Contains($expected)) { throw "Missing override: $expected" }
    }
    if ($output.Contains('go@1.26.0')) { throw 'Manifest tool overrode CLI tool' }
    Invoke-TestCommand $creator @('demo', '--config', $config, '--validate') | Out-Null
    Invoke-TestCommand $creator @('--config', $config, '--create', 'invalid', '--tool', 'python@3.13.0', '--dry-run') 2 | Out-Null
    if (Test-Path "$configDir/profiles/invalid.profile") { throw 'Invalid profile was written' }
    [IO.File]::WriteAllText((Join-Path $project '.pisandboxrc'), "PROFILE=demo`n")
    $output = Invoke-TestCommand $runner @('--config', $config, '--workspace', $project, '--dry-run', '--persist-cli-auth')
    foreach ($expected in @('pi-sandbox-demo:latest', 'pi-agent-demo-gh-auth', 'pi-agent-demo-glab-auth')) {
        if (-not $output.Contains($expected)) { throw "Missing runtime setting: $expected" }
    }
    $output = Invoke-TestCommand $runner @('--config', $config, '--workspace', $project, '--dry-run', '--image', 'custom:tag', '--shell')
    if (-not $output.Contains('--entrypoint /bin/bash custom:tag') -or $output.Contains('gh-auth')) { throw 'Image override/shell ordering or auth opt-in failed' }
    $output = Invoke-TestCommand $runner @('--config', $config, '--workspace', $project, '--reset-cli-auth', '--dry-run')
    if (-not $output.Contains('volume rm pi-agent-demo-gh-auth')) { throw 'Auth reset preview missing' }
    $output = Invoke-TestCommand $runner @('--config', $config, '--workspace', $project, '--doctor', '--dry-run')
    if (-not $output.Contains('Doctor would check Podman')) { throw 'Doctor preview missing' }
    $output = Invoke-TestCommand $runner @('--config', $config, '--workspace', $project, '--doctor')
    if (-not $output.Contains('OK: rootless Podman') -or -not $output.Contains('referenced Podman secret exists: api-token')) { throw "Doctor execution failed: $output" }
    Write-Output 'Windows creation and runtime improvement tests passed.'
}
finally {
    $env:PATH = $oldPath; $env:PODMAN_LOG = $oldLog
    Remove-Item -LiteralPath $work -Recurse -Force
}

