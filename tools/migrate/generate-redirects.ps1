param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsOut = "docs",
  [string]$SiteSrc = "site-src"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$docsRoot = Join-Path $RepoRoot $DocsOut
$dataRoot = Join-Path (Join-Path $RepoRoot $SiteSrc) "data"
$redirectsPath = Join-Path $dataRoot "redirects.json"
if (-not (Test-Path -LiteralPath $redirectsPath)) { throw "Missing redirects data: $redirectsPath" }

$redirects = Get-Content -LiteralPath $redirectsPath -Raw | ConvertFrom-Json
$count = 0
foreach ($r in $redirects) {
  $from = [string]$r.from
  if ([string]::IsNullOrWhiteSpace($from)) { continue }
  $target = [string]$r.to
  $fromTrim = $from.TrimStart("/")
  $outPath = Join-Path $docsRoot ($fromTrim -replace "/", "\")
  $html = New-RedirectHtml -TargetPath $target -LegacyPath $from
  Write-TextFileUtf8NoBom -Path $outPath -Content $html
  $count++
}

Write-Output "Generated $count legacy redirect stubs in $docsRoot"
