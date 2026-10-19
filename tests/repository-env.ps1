#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/windows/pi-sandbox-run.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Runner parse failed' }
$fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-RepositoryEnvironment' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$work = Join-Path ([IO.Path]::GetTempPath()) ('repository-env-' + [guid]::NewGuid())
$oldGlobal = $env:GIT_CONFIG_GLOBAL; $oldSystem = $env:GIT_CONFIG_NOSYSTEM
try {
    New-Item -ItemType Directory $work | Out-Null
    $env:GIT_CONFIG_GLOBAL = Join-Path $work 'empty-gitconfig'
    [IO.File]::WriteAllText($env:GIT_CONFIG_GLOBAL, '')
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $HostWorkspace = Join-Path $work 'project'
    New-Item -ItemType Directory $HostWorkspace | Out-Null
    if (@(Get-RepositoryEnvironment).Count) { throw 'Non-repository produced environment variables' }
    & git init -q $HostWorkspace
    & git -C $HostWorkspace config user.name 'Test Developer'
    & git -C $HostWorkspace config user.email 'dev@example.test'
    & git -C $HostWorkspace remote add origin 'https://alice:neverlog@github.com/team/repo.git?token=neverlog'
    $actual = @(Get-RepositoryEnvironment)
    foreach ($expected in @('GH_HOST=github.com', 'GH_REPO=github.com/team/repo', 'GIT_REMOTE_USER=alice', 'GIT_AUTHOR_NAME=Test Developer', 'GIT_COMMITTER_EMAIL=dev@example.test')) {
        if ($actual -cnotcontains $expected) { throw "Missing $expected" }
    }
    if (($actual -join '|').Contains('neverlog')) { throw 'Remote credentials leaked' }
    & git -C $HostWorkspace remote set-url origin 'git@gitlab.example.test:team/subgroup/repo.git'
    $actual = @(Get-RepositoryEnvironment)
    foreach ($expected in @('GITLAB_HOST=gitlab.example.test', 'GITLAB_REPO=team/subgroup/repo', 'GLAB_API_PROTOCOL=https')) {
        if ($actual -cnotcontains $expected) { throw "Missing $expected" }
    }
    & git -C $HostWorkspace remote set-url origin 'ssh://git@gitlab.example.test:2222/team/repo.git'
    $actual = @(Get-RepositoryEnvironment)
    if ($actual -cnotcontains 'GITLAB_HOST=gitlab.example.test' -or ($actual -join '|').Contains('2222')) { throw 'SSH port used as API port' }
    & git -C $HostWorkspace remote rename origin upstream
    & git -C $HostWorkspace remote set-url upstream 'http://gitlab.example.test:8080/team/repo.git'
    $actual = @(Get-RepositoryEnvironment)
    if ($actual -cnotcontains 'GITLAB_HOST=gitlab.example.test:8080' -or $actual -cnotcontains 'GLAB_API_PROTOCOL=http') { throw 'HTTP remote parsing failed' }
    & git -C $HostWorkspace remote set-url upstream '/tmp/local-repo.git'
    if ((@(Get-RepositoryEnvironment) -join '|') -match 'GH_HOST=') { throw 'Local remote inferred a host' }
    Write-Output 'Windows repository environment tests passed.'
}
finally {
    $env:GIT_CONFIG_GLOBAL = $oldGlobal; $env:GIT_CONFIG_NOSYSTEM = $oldSystem
    Remove-Item -LiteralPath $work -Recurse -Force
}
