param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsOut = "docs",
  [string]$SiteSrc = "site-src"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$docsRoot = Join-Path $RepoRoot $DocsOut
$siteSrcRoot = Join-Path $RepoRoot $SiteSrc
$dataRoot = Join-Path $siteSrcRoot "data"
$redirectsPath = Join-Path $dataRoot "redirects.json"
if (-not (Test-Path -LiteralPath $redirectsPath)) { throw "Missing redirects data: $redirectsPath" }

$projectBasePath = ""
$siteConfigPath = Join-Path $dataRoot "site.json"
if (Test-Path -LiteralPath $siteConfigPath) {
  try {
    $siteConfig = Get-Content -LiteralPath $siteConfigPath -Raw | ConvertFrom-Json
    $projectBasePath = [string]$siteConfig.github_pages_project_base_path
  } catch {
    Write-Warning "Could not read site config for project base path: $_"
  }
}

$redirects = Get-Content -LiteralPath $redirectsPath -Raw | ConvertFrom-Json
$count = 0
foreach ($r in $redirects) {
  $from = [string]$r.from
  if ([string]::IsNullOrWhiteSpace($from)) { continue }
  $target = [string]$r.to
  $fromTrim = $from.TrimStart("/")
  $outPath = Join-Path $docsRoot ($fromTrim -replace "/", "\")
  $html = New-RedirectHtml -TargetPath $target -LegacyPath $from -ProjectBasePath $projectBasePath
  Write-TextFileUtf8NoBom -Path $outPath -Content $html
  $count++
}

Write-Output "Generated $count legacy redirect stubs in $docsRoot"
