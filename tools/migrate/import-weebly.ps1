param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SourceDocs = "docs-source",
  [string]$SiteSrc = "site-src",
  [switch]$CleanContent
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$sourceDocsPath = Join-Path $RepoRoot $SourceDocs
$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$contentRoot = Join-Path $siteSrcPath "content"
$dataRoot = Join-Path $siteSrcPath "data"
$migrationRoot = Join-Path $RepoRoot "migration"

if (-not (Test-Path -LiteralPath $sourceDocsPath)) {
  throw "Source docs directory not found: $sourceDocsPath"
}

Ensure-Directory -Path $contentRoot
Ensure-Directory -Path $dataRoot
Ensure-Directory -Path $migrationRoot

if ($CleanContent) {
  Get-ChildItem -LiteralPath $contentRoot -Force | Remove-Item -Recurse -Force
  Ensure-Directory -Path $contentRoot
}

$htmlFiles = Get-ChildItem -LiteralPath $sourceDocsPath -Filter *.html -File | Sort-Object Name
$pages = New-Object System.Collections.Generic.List[object]
$redirects = New-Object System.Collections.Generic.List[object]
$urlMapRows = New-Object System.Collections.Generic.List[object]
$taxonomyCounts = @{}

$hiddenPatterns = @(
  '^teamtest',
  '^oldcode$',
  '^[1278]$'
)

foreach ($file in $htmlFiles) {
  $legacyFile = $file.Name
  $legacyName = [System.IO.Path]::GetFileNameWithoutExtension($legacyFile)
  $legacyNameLower = $legacyName.ToLowerInvariant()
  $canonicalRoute = Get-CanonicalPageRoute -LegacyHtmlFilename $legacyFile

  $status = "published"
  foreach ($pat in $hiddenPatterns) {
    if ($legacyNameLower -match $pat) { $status = "hidden"; break }
  }

  $section = ($canonicalRoute.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries) | Select-Object -First 1)
  if ($null -eq $section) { $section = "root" }
  if ([string]::IsNullOrWhiteSpace($section)) { $section = "root" }
  if ($taxonomyCounts.ContainsKey($section)) { $taxonomyCounts[$section]++ } else { $taxonomyCounts[$section] = 1 }

  $html = Read-TextFileSafe -Path $file.FullName
  $parts = Get-HtmlDocumentParts -Html $html

  $canonicalSegments = @()
  if ($canonicalRoute -ne "/") {
    $canonicalSegments = $canonicalRoute.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
  }
  $pageDir = if ($canonicalSegments.Count -eq 0) { Join-Path $contentRoot "home" } else { Join-Path $contentRoot ([System.IO.Path]::Combine($canonicalSegments)) }
  Ensure-Directory -Path $pageDir

  $bodyPath = Join-Path $pageDir "body.html"
  $headPath = Join-Path $pageDir "head.raw.html"
  $sourceHtmlPath = Join-Path $pageDir "original.html"
  $metaPath = Join-Path $pageDir "index.page.json"

  Write-TextFileUtf8NoBom -Path $bodyPath -Content $parts.BodyInner
  Write-TextFileUtf8NoBom -Path $headPath -Content $parts.HeadInner
  Write-TextFileUtf8NoBom -Path $sourceHtmlPath -Content $html

  $pageId = ConvertTo-Slug -Text $legacyName
  $meta = [ordered]@{
    id = $pageId
    legacy_path = $legacyFile
    legacy_name = $legacyName
    canonical_path = $canonicalRoute
    title = $parts.Title
    description = $parts.MetaDescription
    section = $section
    subcategory = if ($canonicalSegments.Count -gt 1) { $canonicalSegments[1] } else { "" }
    layout = if ($section -in @("bulletin", "research", "media", "events")) { "article" } else { "page" }
    nav_group = $section
    order = 0
    body_fragment = (Get-RelativePathUnix -Root $siteSrcPath -Path $bodyPath)
    head_fragment = (Get-RelativePathUnix -Root $siteSrcPath -Path $headPath)
    source_html = (Get-RelativePathUnix -Root $siteSrcPath -Path $sourceHtmlPath)
    page_css = ""
    page_js = ""
    html_tag_attributes = $parts.HtmlTagAttributes
    body_tag_attributes = $parts.BodyTagAttributes
    status = $status
    redirect_legacy = $true
  }

  ($meta | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $metaPath -Encoding utf8
  $pages.Add([pscustomobject]$meta)

  if ($legacyFile -ne "index.html") {
    $redirects.Add([pscustomobject]@{
      from = "/" + $legacyFile
      to = $canonicalRoute
      type = "legacy-html-page"
    })
  }

  $urlMapRows.Add([pscustomobject]@{
    legacy_path = $legacyFile
    canonical_path = $canonicalRoute
    status = $status
    title = $parts.Title
  })
}

$pagesJsonPath = Join-Path $dataRoot "pages.json"
$redirectsJsonPath = Join-Path $dataRoot "redirects.json"
$taxonomyJsonPath = Join-Path $dataRoot "taxonomy.json"
$siteJsonPath = Join-Path $dataRoot "site.json"
$navYamlPath = Join-Path $dataRoot "nav.yaml"

($pages | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $pagesJsonPath -Encoding utf8
($redirects | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $redirectsJsonPath -Encoding utf8
([pscustomobject]@{ sections = $taxonomyCounts } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $taxonomyJsonPath -Encoding utf8
([pscustomobject]@{
    title = "Alius"
    source = "Weebly export"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    page_count = $pages.Count
    canonical_url_strategy = "hierarchical+redirects"
  } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $siteJsonPath -Encoding utf8

Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "pages.yaml") -Items $pages -KeyOrder @(
  "id","legacy_path","canonical_path","title","description","section","subcategory","layout","nav_group",
  "order","body_fragment","head_fragment","source_html","page_css","page_js","status","redirect_legacy"
)
Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "redirects.yaml") -Items $redirects -KeyOrder @("from","to","type")
Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "taxonomy.yaml") -Items @(
  foreach ($k in ($taxonomyCounts.Keys | Sort-Object)) {
    [pscustomobject]@{ section = $k; count = $taxonomyCounts[$k] }
  }
) -KeyOrder @("section","count")
Write-LinesUtf8NoBom -Path $navYamlPath -Lines @(
  "# Placeholder nav data for future template-driven nav rendering.",
  "# Current build preserves page HTML and rewrites links; nav extraction artifacts are in site-src/partials/*.raw.html"
)

$urlMapCsv = Join-Path $migrationRoot "legacy-to-canonical-url-map.csv"
$urlMapRows | Export-Csv -LiteralPath $urlMapCsv -NoTypeInformation -Encoding UTF8

Write-Output "Imported $($pages.Count) HTML pages into $contentRoot"
Write-Output "Wrote page metadata: $pagesJsonPath"
Write-Output "Wrote redirects data: $redirectsJsonPath"
Write-Output "Wrote URL map: $urlMapCsv"
