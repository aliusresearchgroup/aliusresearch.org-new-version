param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$BackupRoot = "C:\Users\cogpsy-vrlab\Proton Drive\George.Fejer\My files\aliusresearch.org-originals"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\migrate\Migration.Common.ps1")

$manifestPath = Join-Path $RepoRoot "migration\proton-backup-manifest.csv"
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Backup manifest not found: $manifestPath. Run tools/migrate/dedupe-assets.ps1 first."
}

Write-Output "Backup copies are performed during tools/migrate/dedupe-assets.ps1."
Write-Output "Manifest: $manifestPath"
Write-Output "Backup root: $BackupRoot"
