param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [switch]$SkipBackup,
  [switch]$SkipVendorDownload
)

$ErrorActionPreference = "Stop"

Write-Output "1/8 Importing pages and generating source model..."
& (Join-Path $PSScriptRoot "import-weebly.ps1") -RepoRoot $RepoRoot

Write-Output "2/8 Extracting common partials..."
& (Join-Path $PSScriptRoot "extract-partials.ps1") -RepoRoot $RepoRoot

Write-Output "3/8 Dedupe/canonicalize assets and PDFs..."
& (Join-Path $PSScriptRoot "dedupe-assets.ps1") -RepoRoot $RepoRoot @(
  if ($SkipBackup) { "-SkipBackup" }
)

Write-Output "4/8 Vendoring Weebly/EditMySite assets..."
& (Join-Path $PSScriptRoot "vendor-weebly-assets.ps1") -RepoRoot $RepoRoot @(
  if ($SkipVendorDownload) { "-SkipDownload" }
)

Write-Output "5/8 Rewriting page links/assets/CDN URLs..."
& (Join-Path $PSScriptRoot "rewrite-links.ps1") -RepoRoot $RepoRoot

Write-Output "6/8 Building hierarchical docs output + redirects..."
& (Join-Path $PSScriptRoot "build-site.ps1") -RepoRoot $RepoRoot -CleanDocs

Write-Output "7/8 Running media optimization check..."
& (Join-Path $PSScriptRoot "optimize-media.ps1") -RepoRoot $RepoRoot

Write-Output "8/8 Running audits..."
& (Join-Path (Join-Path $RepoRoot "tools\audit") "redundancy-report.ps1") -RepoRoot $RepoRoot -DocsDir "docs-source"
& (Join-Path (Join-Path $RepoRoot "tools\audit") "size-budget-check.ps1") -RepoRoot $RepoRoot -DocsDir "docs"
& (Join-Path (Join-Path $RepoRoot "tools\audit") "link-check.ps1") -RepoRoot $RepoRoot -DocsDir "docs"

Write-Output "Migration pipeline complete."
