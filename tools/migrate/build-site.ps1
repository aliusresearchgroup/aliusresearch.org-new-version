param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsOut = "docs",
  [string]$SiteSrc = "site-src",
  [switch]$CleanDocs
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$dataRoot = Join-Path $siteSrcPath "data"
$staticRoot = Join-Path $siteSrcPath "static"
$docsRoot = Join-Path $RepoRoot $DocsOut
$migrationRoot = Join-Path $RepoRoot "migration"
Ensure-Directory -Path $migrationRoot

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

if ($CleanDocs -and (Test-Path -LiteralPath $docsRoot)) {
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $backupDocs = Join-Path $RepoRoot ("docs-prev-" + $stamp)
  try {
    Rename-Item -LiteralPath $docsRoot -NewName (Split-Path -Leaf $backupDocs)
  } catch {
    Write-Warning "Could not rename existing docs output; proceeding without cleanup. $_"
  }
}
Ensure-Directory -Path $docsRoot

# Copy static assets into docs root.
if (Test-Path -LiteralPath $staticRoot) {
  Get-ChildItem -LiteralPath $staticRoot -Recurse -File | ForEach-Object {
    $rel = Get-RelativePathUnix -Root $staticRoot -Path $_.FullName
    if ($rel -match '(^|/)[^/]+\.prev-\d{8}-\d{6}(/|$)') {
      return
    }
    $dest = Join-Path $docsRoot ($rel -replace "/", "\")
    Copy-FilePreserveTimestamp -SourcePath $_.FullName -DestinationPath $dest
  }
}

$pages = Get-Content -LiteralPath (Join-Path $dataRoot "pages.json") -Raw | ConvertFrom-Json
$rewrittenIndexPath = Join-Path $migrationRoot "rewritten-page-sources.csv"
$rewrittenLookup = @{}
if (Test-Path -LiteralPath $rewrittenIndexPath) {
  foreach ($row in (Import-Csv $rewrittenIndexPath)) {
    $rewrittenLookup[[string]$row.legacy_path] = [string]$row.rewritten_html
  }
}

$pageCount = 0
foreach ($page in $pages) {
  $legacy = [string]$page.legacy_path
  $canonical = [string]$page.canonical_path
  $sourceRel = if ($rewrittenLookup.ContainsKey($legacy)) { $rewrittenLookup[$legacy] } else { [string]$page.source_html }
  $sourceAbs = Join-Path $siteSrcPath ($sourceRel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $sourceAbs)) {
    Write-Warning "Missing source for page ${legacy}: $sourceAbs"
    continue
  }
  $html = Read-TextFileSafe -Path $sourceAbs
  $html = Add-ProjectBasePathToRootRelativeUrls -Text $html -BasePath $projectBasePath

  if ($canonical -eq "/") {
    $outPath = Join-Path $docsRoot "index.html"
  } else {
    $routeSegments = $canonical.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
    $dir = Join-Path $docsRoot ([System.IO.Path]::Combine($routeSegments))
    $outPath = Join-Path $dir "index.html"
  }

  Write-TextFileUtf8NoBom -Path $outPath -Content $html
  $pageCount++
}

Write-TextFileUtf8NoBom -Path (Join-Path $docsRoot ".nojekyll") -Content ""

& (Join-Path $PSScriptRoot "generate-redirects.ps1") -RepoRoot $RepoRoot -DocsOut $DocsOut -SiteSrc $SiteSrc | Out-Null

if (-not [string]::IsNullOrWhiteSpace((Normalize-ProjectBasePath -BasePath $projectBasePath))) {
  # Ensure inline and external CSS assets also resolve under project Pages subpath.
  Get-ChildItem -LiteralPath $docsRoot -Recurse -Include *.css -File | ForEach-Object {
    try {
      $css = Read-TextFileSafe -Path $_.FullName
      $rewritten = Add-ProjectBasePathToRootRelativeUrls -Text $css -BasePath $projectBasePath
      if ($rewritten -ne $css) {
        Write-TextFileUtf8NoBom -Path $_.FullName -Content $rewritten
      }
    } catch {
      Write-Warning "Failed project-base rewrite for CSS $($_.FullName): $_"
    }
  }
}

$summary = @(
  "Generated UTC: $([DateTime]::UtcNow.ToString('o'))",
  "Docs output: $docsRoot",
  "Canonical pages written: $pageCount",
  "Static root copied: $staticRoot",
  "Redirect stubs: $(if (Test-Path -LiteralPath (Join-Path $dataRoot 'redirects.json')) { (Get-Content -LiteralPath (Join-Path $dataRoot 'redirects.json') -Raw | ConvertFrom-Json).Count } else { 0 })",
  "GitHub Pages project base path: $(if ([string]::IsNullOrWhiteSpace((Normalize-ProjectBasePath -BasePath $projectBasePath))) { '(none)' } else { Normalize-ProjectBasePath -BasePath $projectBasePath })"
)
Write-LinesUtf8NoBom -Path (Join-Path $migrationRoot "build-summary.txt") -Lines $summary

Write-Output "Built canonical site into $docsRoot ($pageCount pages + static assets + redirects)"
