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

function Get-CleanDisplayTitle {
  param([AllowEmptyString()][string]$Title)
  if ([string]::IsNullOrWhiteSpace($Title)) { return "" }
  $t = $Title -replace '\s*-\s*Alius\s*$', ''
  $t = $t -replace '&#8203;|&#x200B;|&#8204;|&#65279;', ''
  $t = $t -replace '\s+', ' '
  return $t.Trim()
}

function Get-SectionLabel {
  param([AllowEmptyString()][string]$Section)
  $s = if ($null -eq $Section) { "" } else { [string]$Section }
  switch ($s.ToLowerInvariant()) {
    "about" { return "About" }
    "articles" { return "Articles" }
    "archive" { return "Archive" }
    "bulletin" { return "Bulletin" }
    "community" { return "Community" }
    "events" { return "Events" }
    "media" { return "Media" }
    "pages" { return "Pages" }
    "research" { return "Research" }
    "root" { return "Home" }
    default { return "Pages" }
  }
}

function Get-SubcategoryLabel {
  param([AllowEmptyString()][string]$Subcategory)
  if ([string]::IsNullOrWhiteSpace($Subcategory)) { return "" }
  $parts = $Subcategory -replace '[_-]+', ' ' -split '\s+' | Where-Object { $_ }
  $titled = foreach ($p in $parts) {
    if ($p.Length -le 3 -and $p -cmatch '^[a-z]+$') { $p.ToUpperInvariant() }
    else { $p.Substring(0,1).ToUpperInvariant() + $p.Substring(1) }
  }
  return ($titled -join " ")
}

function Get-SectionRootCanonicalPath {
  param([Parameter(Mandatory = $true)][object]$Page)
  $section = [string]$Page.section
  $s = if ($null -eq $section) { "" } else { [string]$section }
  switch ($s.ToLowerInvariant()) {
    "root" { return "/" }
    "about" { return "/about/" }
    "research" { return "/research/" }
    "bulletin" { return "/bulletin/" }
    "events" { return "/events/events/" }
    "media" { return "/media/media/" }
    "community" { return "/community/become-a-member/" }
    "articles" { return "/articles/interviews/interviews/" }
    "pages" { return "/pages/" }
    "archive" { return "/archive/misc/" }
    default { return "/" }
  }
}

function New-AliusBreadcrumbHtml {
  param(
    [Parameter(Mandatory = $true)][object]$Page,
    [Parameter(Mandatory = $true)][hashtable]$PublishedPagesByCanonical,
    [AllowEmptyString()][string]$ProjectBasePath
  )
  $canonical = [string]$Page.canonical_path
  if ($canonical -eq "/") { return "" }

  $pageTitle = Get-CleanDisplayTitle -Title ([string]$Page.title)
  $sectionLabel = Get-SectionLabel -Section ([string]$Page.section)
  $subcategoryLabel = Get-SubcategoryLabel -Subcategory ([string]$Page.subcategory)
  $sectionRootCanonical = Get-SectionRootCanonicalPath -Page $Page

  $crumbs = New-Object System.Collections.Generic.List[object]
  $crumbs.Add([pscustomobject]@{
      Label = "Home"
      Href = (Add-ProjectBasePathToPath -Path "/" -BasePath $ProjectBasePath)
      Current = $false
    }) | Out-Null

  if ($canonical -ne "/" -and $sectionRootCanonical -ne "/" -and ($PublishedPagesByCanonical.ContainsKey($sectionRootCanonical) -or $sectionLabel)) {
    $crumbs.Add([pscustomobject]@{
        Label = $sectionLabel
        Href = (Add-ProjectBasePathToPath -Path $sectionRootCanonical -BasePath $ProjectBasePath)
        Current = $false
      }) | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($subcategoryLabel)) {
    $isDistinctFromTitle = ($subcategoryLabel.ToLowerInvariant() -ne $pageTitle.ToLowerInvariant())
    if ($isDistinctFromTitle) {
      $crumbs.Add([pscustomobject]@{
          Label = $subcategoryLabel
          Href = ""
          Current = $false
        }) | Out-Null
    }
  }

  $crumbs.Add([pscustomobject]@{
      Label = $(if ([string]::IsNullOrWhiteSpace($pageTitle)) { $sectionLabel } else { $pageTitle })
      Href = ""
      Current = $true
    }) | Out-Null

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine('<div class="alius-page-context" aria-label="Page context">')
  [void]$sb.AppendLine('  <div class="alius-page-context-inner">')
  [void]$sb.AppendLine('    <nav class="alius-breadcrumbs" aria-label="Breadcrumb">')
  $i = 0
  foreach ($c in $crumbs) {
    if ($i -gt 0) { [void]$sb.AppendLine('      <span class="alius-breadcrumb-sep" aria-hidden="true">/</span>') }
    if ($c.Current) {
      [void]$sb.AppendLine(('      <span class="alius-breadcrumb-current" aria-current="page">{0}</span>' -f [System.Web.HttpUtility]::HtmlEncode([string]$c.Label)))
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$c.Href)) {
      [void]$sb.AppendLine(('      <a class="alius-breadcrumb-link" href="{0}">{1}</a>' -f [string]$c.Href, [System.Web.HttpUtility]::HtmlEncode([string]$c.Label)))
    } else {
      [void]$sb.AppendLine(('      <span class="alius-breadcrumb-link">{0}</span>' -f [System.Web.HttpUtility]::HtmlEncode([string]$c.Label)))
    }
    $i++
  }
  [void]$sb.AppendLine('    </nav>')
  [void]$sb.AppendLine(('    <div class="alius-page-context-meta"><span class="alius-page-context-pill alius-section-pill">{0}</span>{1}</div>' -f `
      [System.Web.HttpUtility]::HtmlEncode($sectionLabel), `
      $(if ([string]::IsNullOrWhiteSpace($subcategoryLabel)) { "" } else { '<span class="alius-page-context-pill alius-subcategory-pill">' + [System.Web.HttpUtility]::HtmlEncode($subcategoryLabel) + '</span>' })))
  [void]$sb.AppendLine('  </div>')
  [void]$sb.AppendLine('</div>')
  return $sb.ToString()
}

function New-AliusHomeExploreHtml {
  param(
    [Parameter(Mandatory = $true)][hashtable]$PublishedPagesByCanonical,
    [AllowEmptyString()][string]$ProjectBasePath
  )

  $cards = @(
    @{ label = "Bulletin"; desc = "Interviews, issues, and annual releases."; path = "/bulletin/" }
    @{ label = "Research"; desc = "Projects, commentaries, and ongoing work."; path = "/research/" }
    @{ label = "Events"; desc = "Workshops, talks, and archived events."; path = "/events/events/" }
    @{ label = "Team"; desc = "Coordinators, members, and collaborators."; path = "/about/team/team/" }
    @{ label = "Media"; desc = "Podcast, music, and visual content."; path = "/media/media/" }
    @{ label = "Membership"; desc = "Ways to support and participate in ALIUS."; path = "/community/become-a-member/" }
  )

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine('<section class="alius-home-explore" aria-labelledby="alius-home-explore-title">')
  [void]$sb.AppendLine('  <div class="container alius-home-explore-container">')
  [void]$sb.AppendLine('    <div class="alius-home-explore-header">')
  [void]$sb.AppendLine('      <h2 id="alius-home-explore-title" class="alius-home-explore-title">Explore ALIUS</h2>')
  [void]$sb.AppendLine("      <p class=`"alius-home-explore-subtitle`">A clearer path into the group's publications, events, research projects, and community.</p>")
  [void]$sb.AppendLine('    </div>')
  [void]$sb.AppendLine('    <div class="alius-home-explore-grid">')
  foreach ($card in $cards) {
    $href = Add-ProjectBasePathToPath -Path ([string]$card.path) -BasePath $ProjectBasePath
    [void]$sb.AppendLine(('      <a class="alius-home-card" href="{0}"><span class="alius-home-card-label">{1}</span><span class="alius-home-card-desc">{2}</span><span class="alius-home-card-cta">Open</span></a>' -f `
      $href, [System.Web.HttpUtility]::HtmlEncode([string]$card.label), [System.Web.HttpUtility]::HtmlEncode([string]$card.desc)))
  }
  [void]$sb.AppendLine('    </div>')
  [void]$sb.AppendLine('  </div>')
  [void]$sb.AppendLine('</section>')
  return $sb.ToString()
}

function Add-AliusRefinedAssetsAndMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][object]$Page,
    [AllowEmptyString()][string]$ProjectBasePath
  )

  $result = $Html
  $section = ([string]$Page.section).ToLowerInvariant()
  $layout = ([string]$Page.layout).ToLowerInvariant()
  $subcategory = ([string]$Page.subcategory).ToLowerInvariant()
  $canonical = [string]$Page.canonical_path

  $bodyMatch = [regex]::Match($result, '(?is)<body\b([^>]*)>')
  if ($bodyMatch.Success) {
    $attrs = $bodyMatch.Groups[1].Value
    if ($attrs -match '\bclass\s*=\s*"([^"]*)"') {
      $existing = $Matches[1]
      $classes = @($existing, 'alius-refined', "alius-section-$section", "alius-layout-$layout")
      if (-not [string]::IsNullOrWhiteSpace($subcategory)) { $classes += "alius-subcategory-$subcategory" }
      $newClass = ($classes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
      $attrs = [regex]::Replace($attrs, '\bclass\s*=\s*"[^"]*"', ('class="' + $newClass + '"'))
    } else {
      $attrs += (' class="alius-refined alius-section-' + $section + ' alius-layout-' + $layout + '"')
    }
    if ($attrs -notmatch '\bdata-alius-canonical=') {
      $attrs += (' data-alius-canonical="' + [System.Web.HttpUtility]::HtmlAttributeEncode($canonical) + '"')
    }
    if ($attrs -notmatch '\bdata-alius-section=') {
      $attrs += (' data-alius-section="' + [System.Web.HttpUtility]::HtmlAttributeEncode([string]$Page.section) + '"')
    }
    if ($attrs -notmatch '\bdata-alius-layout=') {
      $attrs += (' data-alius-layout="' + [System.Web.HttpUtility]::HtmlAttributeEncode([string]$Page.layout) + '"')
    }
    $newBodyTag = '<body' + $attrs + '>'
    $result = $result.Substring(0, $bodyMatch.Index) + $newBodyTag + $result.Substring($bodyMatch.Index + $bodyMatch.Length)
  }

  $cssHref = Add-ProjectBasePathToPath -Path "/assets/css/alius-refined.css" -BasePath $ProjectBasePath
  $jsSrc = Add-ProjectBasePathToPath -Path "/assets/js/alius-refined.js" -BasePath $ProjectBasePath
  if ($result -notmatch [regex]::Escape($cssHref)) {
    $result = [regex]::Replace($result, '(?is)</head>', ('<link rel="stylesheet" type="text/css" href="' + $cssHref + '" />' + "`r`n</head>"))
  }
  if ($result -notmatch [regex]::Escape($jsSrc)) {
    $result = [regex]::Replace($result, '(?is)</body>', ('<script defer src="' + $jsSrc + '"></script>' + "`r`n</body>"))
  }

  return $result
}

function Add-AliusRefinedPageChrome {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][object]$Page,
    [Parameter(Mandatory = $true)][hashtable]$PublishedPagesByCanonical,
    [AllowEmptyString()][string]$ProjectBasePath
  )

  $result = $Html
  $canonical = [string]$Page.canonical_path
  $breadcrumbHtml = New-AliusBreadcrumbHtml -Page $Page -PublishedPagesByCanonical $PublishedPagesByCanonical -ProjectBasePath $ProjectBasePath
  if (-not [string]::IsNullOrWhiteSpace($breadcrumbHtml)) {
    $result = [regex]::Replace($result, '(?is)(<div id="content-wrapper">)', ($breadcrumbHtml + "`r`n`$1"))
  }

  if ($canonical -eq "/" -and $result -notmatch 'alius-home-explore') {
    $homePanel = New-AliusHomeExploreHtml -PublishedPagesByCanonical $PublishedPagesByCanonical -ProjectBasePath $ProjectBasePath
    $result = [regex]::Replace($result, '(?is)(<div id="footer">)', ($homePanel + "`r`n`$1"))
  }

  return $result
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
$publishedPagesByCanonical = @{}
foreach ($p in $pages) {
  if ([string]$p.status -ne "published") { continue }
  $publishedPagesByCanonical[[string]$p.canonical_path] = $p
}

# Build a small client-side page index for runtime enhancements (TOC/local section links).
$pageIndexOut = Join-Path $docsRoot "assets\data\alius-page-index.json"
$pageIndexRows = @(
  foreach ($p in $pages) {
    if ([string]$p.status -ne "published") { continue }
    [pscustomobject]@{
      id = [string]$p.id
      canonical_path = [string]$p.canonical_path
      section = [string]$p.section
      subcategory = [string]$p.subcategory
      layout = [string]$p.layout
      title = (Get-CleanDisplayTitle -Title ([string]$p.title))
      description = [string]$p.description
    }
  }
)
Write-TextFileUtf8NoBom -Path $pageIndexOut -Content ($pageIndexRows | ConvertTo-Json -Depth 4)

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
  $html = Add-AliusRefinedAssetsAndMetadata -Html $html -Page $page -ProjectBasePath $projectBasePath
  $html = Add-AliusRefinedPageChrome -Html $html -Page $page -PublishedPagesByCanonical $publishedPagesByCanonical -ProjectBasePath $projectBasePath
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
