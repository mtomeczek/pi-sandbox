#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

& (Join-Path $PSScriptRoot 'scripts\windows\pi-sandbox-create.ps1') @args
