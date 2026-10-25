#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'scripts/windows/pi-sandbox-run.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('repository-env-' + [guid]::NewGuid())
$oldPath = $env:PATH; $oldRepo = $env:GH_REPO
try {
    $configDir = Join-Path $work 'config'
    $allowed = Join-Path $work 'allowed'
    $project = Join-Path $allowed 'project'
    $bin = Join-Path $work 'bin'
    New-Item -ItemType Directory $project, $bin, "$configDir/profiles" | Out-Null
    $config = Join-Path $configDir 'config'
    [IO.File]::WriteAllText($config, '')
    [IO.File]::WriteAllText((Join-Path $configDir 'allowed-roots'), "$allowed`n")
    & git init -q $project
    if ($LASTEXITCODE -ne 0) { throw 'Git fixture creation failed' }
    & git -C $project config user.name 'Test Developer'
    & git -C $project config user.email 'dev@example.test'
    & git -C $project remote add origin 'https://alice:neverlog@github.com/team/repo.git'
    # Dry-run requires a Podman command but must not execute it or Git.
    [IO.File]::WriteAllText((Join-Path $bin 'podman.ps1'), 'throw "Unexpected Podman execution"')
    [IO.File]::WriteAllText((Join-Path $bin 'git.ps1'), 'throw "Unexpected Git execution"')
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$oldPath"
    $output = @(& pwsh -NoProfile -File $runner --config $config --workspace $project --dry-run 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Runner failed: $output" }
    if ($output -match 'GH_HOST|GH_REPO|GITLAB_HOST|GITLAB_REPO|GLAB_API_PROTOCOL|GIT_AUTHOR_|GIT_COMMITTER_|GIT_REMOTE_|neverlog|Unexpected Git') {
        throw 'Automatic repository environment setup remains'
    }
    [IO.File]::WriteAllText((Join-Path $configDir 'profiles/demo.profile'), "ENV=GH_HOST=manual.example.test`nENV_SECRET=GITLAB_TOKEN=manual-token`n")
    $env:GH_REPO = 'manual/project'
    $output = @(& pwsh -NoProfile -File $runner demo --config $config --workspace $project --dry-run --env GH_REPO 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Explicit environment setup failed: $output" }
    foreach ($expected in @('GH_HOST=<redacted>', 'manual-token,type=env,target=GITLAB_TOKEN', '--env GH_REPO')) {
        if (-not $output.Contains($expected)) { throw "Missing explicit setting: $expected" }
    }
    Write-Output 'Windows user-managed repository authentication tests passed.'
}
finally {
    $env:PATH = $oldPath; $env:GH_REPO = $oldRepo
    Remove-Item -LiteralPath $work -Recurse -Force
}

