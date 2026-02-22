param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "import-weebly.ps1") -RepoRoot $RepoRoot
