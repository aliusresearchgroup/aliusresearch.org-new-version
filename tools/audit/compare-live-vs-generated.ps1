param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsOut = "docs",
  [string]$SiteSrc = "site-src",
  [string]$BaseUrl = "https://www.aliusresearch.org",
  [int]$TimeoutSec = 45,
  [int]$DelayMs = 150
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "..\migrate\Migration.Common.ps1")

$docsRoot = Join-Path $RepoRoot $DocsOut
$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$dataRoot = Join-Path $siteSrcPath "data"
$migrationRoot = Join-Path $RepoRoot "migration"
Ensure-Directory -Path $migrationRoot

if (-not (Test-Path -LiteralPath $docsRoot)) {
  throw "Docs output not found: $docsRoot"
}

$pagesPath = Join-Path $dataRoot "pages.json"
if (-not (Test-Path -LiteralPath $pagesPath)) {
  throw "Pages manifest not found: $pagesPath"
}

$pages = Get-Content -LiteralPath $pagesPath -Raw | ConvertFrom-Json

function Get-StringSha256 {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
  }
  finally {
    $sha.Dispose()
  }
}

function Get-LivePageUrl {
  param([Parameter(Mandatory = $true)][string]$LegacyPath)
  if ($LegacyPath -eq "index.html") {
    return ($BaseUrl.TrimEnd("/") + "/")
  }
  return ($BaseUrl.TrimEnd("/") + "/" + $LegacyPath.TrimStart("/"))
}

function Get-CanonicalPageOutputPath {
  param([Parameter(Mandatory = $true)]$Page)
  $canonical = [string]$Page.canonical_path
  if ($canonical -eq "/") {
    return (Join-Path $docsRoot "index.html")
  }
  $segments = $canonical.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
  return (Join-Path (Join-Path $docsRoot ([System.IO.Path]::Combine($segments))) "index.html")
}

function Invoke-PageFetch {
  param([Parameter(Mandatory = $true)][string]$Url)

  $headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36"
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  }

  try {
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -Headers $headers
    return [pscustomobject]@{
      status = [int]$resp.StatusCode
      html = [string]$resp.Content
      error = ""
    }
  }
  catch {
    $statusCode = 0
    try {
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
    } catch {}
    return [pscustomobject]@{
      status = $statusCode
      html = ""
      error = $_.Exception.Message
    }
  }
}

function Normalize-UrlTokenForCompare {
  param([Parameter(Mandatory = $true)][string]$Token)

  $t = $Token.Trim()
  if ([string]::IsNullOrWhiteSpace($t)) { return "[URL_EMPTY]" }

  # Strip quotes if captured inside CSS url(...)
  $t = $t.Trim("'").Trim('"')

  # Keep query/hash out of visual-structure comparison.
  $pathOnly = ($t -split '[?#]', 2)[0]
  if ([string]::IsNullOrWhiteSpace($pathOnly)) { $pathOnly = $t }

  if ($pathOnly -match '^https?://') {
    try {
      $uri = [Uri]$pathOnly
      $host = $uri.Host.ToLowerInvariant()
      $leaf = [IO.Path]::GetFileName($uri.AbsolutePath)
      $ext = [IO.Path]::GetExtension($uri.AbsolutePath).ToLowerInvariant()
      if ($host -match '(?:aliusresearch\.org)$') {
        $pathOnly = $uri.AbsolutePath
      }
      else {
        if ([string]::IsNullOrWhiteSpace($ext)) { return "[URL_EXT_LINK]" }
        return "[URL_ASSET:${ext}:${leaf}]"
      }
    } catch {
      return "[URL_EXT]"
    }
  }
  elseif ($pathOnly.StartsWith("//")) {
    try {
      $uri = [Uri]("https:" + $pathOnly)
      $host = $uri.Host.ToLowerInvariant()
      $leaf = [IO.Path]::GetFileName($uri.AbsolutePath)
      $ext = [IO.Path]::GetExtension($uri.AbsolutePath).ToLowerInvariant()
      if ([string]::IsNullOrWhiteSpace($ext)) { return "[URL_EXT_LINK]" }
      return "[URL_ASSET:${ext}:${leaf}]"
    } catch {
      return "[URL_SCHEME_REL]"
    }
  }

  if ($pathOnly -match '^(?:mailto:|tel:|javascript:|data:|#)') {
    return "[URL_NONVISUAL]"
  }

  if (-not $pathOnly.StartsWith("/")) {
    $pathOnly = "/" + $pathOnly
  }

  $leafName = [IO.Path]::GetFileName($pathOnly)
  $ext2 = [IO.Path]::GetExtension($pathOnly).ToLowerInvariant()

  if ($pathOnly -match '^/(?:uploads|files|apps|assets|media|gdpr|cdn-cgi)/') {
    if ([string]::IsNullOrWhiteSpace($ext2)) { return "[URL_LOCAL_PATH]" }
    return "[URL_ASSET:${ext2}:${leafName}]"
  }

  # Treat all internal page links as equivalent for appearance comparison.
  if (($ext2 -eq ".html") -or [string]::IsNullOrWhiteSpace($ext2)) {
    return "[URL_PAGE]"
  }

  return "[URL_ASSET:${ext2}:${leafName}]"
}

function Normalize-HtmlForVisualCompare {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Html)

  if ([string]::IsNullOrWhiteSpace($Html)) { return "" }
  $out = $Html

  # Normalize line endings and remove comments.
  $out = $out -replace "`r`n?", "`n"
  $out = [regex]::Replace($out, '(?is)<!--(?!\[if).*?-->', '')

  # Scripts are the biggest source of non-visual drift (build times, analytics, commerce blobs).
  $out = [regex]::Replace($out, '(?is)<script\b[^>]*>.*?</script>', '')

  # Normalize href/src URLs.
  $out = [regex]::Replace(
    $out,
    '(?is)\b(?<attr>href|src)\s*=\s*(?<q>["''])(?<url>[^"'']+)(?<q2>["''])',
    {
      param($m)
      $norm = Normalize-UrlTokenForCompare -Token $m.Groups['url'].Value
      return ($m.Groups['attr'].Value + "=" + $m.Groups['q'].Value + $norm + $m.Groups['q2'].Value)
    }
  )

  # Normalize CSS url(...)
  $out = [regex]::Replace(
    $out,
    '(?is)url\(\s*(?<q>["'']?)(?<url>[^)''""]+)(?<q2>["'']?)\s*\)',
    {
      param($m)
      $norm = Normalize-UrlTokenForCompare -Token $m.Groups['url'].Value
      $q1 = $m.Groups['q'].Value
      $q2 = $m.Groups['q2'].Value
      if ([string]::IsNullOrEmpty($q1) -and -not [string]::IsNullOrEmpty($q2)) { $q1 = $q2 }
      if ([string]::IsNullOrEmpty($q2) -and -not [string]::IsNullOrEmpty($q1)) { $q2 = $q1 }
      return ("url(" + $q1 + $norm + $q2 + ")")
    }
  )

  # Normalize whitespace and query-like build numbers that can remain in text/style blocks.
  $out = $out -replace 'buildTime=\d+', 'buildTime=<N>'
  $out = $out -replace '\?1760\d+', '?<N>'
  $out = [regex]::Replace($out, '\s+', ' ')
  $out = $out.Trim()
  return $out
}

function Extract-NavBlock {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][ValidateSet('desktop','mobile')][string]$Which
  )

  if ($Which -eq 'desktop') {
    return (Try-GetRegexMatchValue -Text $Html -Pattern '<div id="navigation">\s*(.*?)\s*</div>\s*<div class="banner-wrap">' )
  }

  return (Try-GetRegexMatchValue -Text $Html -Pattern '<div id="navmobile"[^>]*>\s*(.*?)\s*</div>\s*</div>\s*</div>\s*(?:<script|</body>)')
}

function Get-MenuTextSignature {
  param([AllowEmptyString()][string]$NavBlockHtml)
  if ([string]::IsNullOrWhiteSpace($NavBlockHtml)) { return "" }
  $texts = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($NavBlockHtml, '(?is)<a\b[^>]*class=["''][^"'']*wsite-menu-item[^"'']*["''][^>]*>(.*?)</a>')) {
    $inner = [regex]::Replace($m.Groups[1].Value, '(?is)<[^>]+>', ' ')
    $inner = [regex]::Replace($inner, '\s+', ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($inner)) { [void]$texts.Add($inner) }
  }
  return ($texts -join " | ")
}

function Get-ThemeAssetFlags {
  param([Parameter(Mandatory = $true)][string]$Html)
  return [pscustomobject]@{
    has_main_style = [bool]([regex]::IsMatch($Html, '(?is)main_style\.css'))
    has_theme_plugins = [bool]([regex]::IsMatch($Html, '(?is)(?:plugins\.js)'))
    has_theme_custom = [bool]([regex]::IsMatch($Html, '(?is)(?:custom\.js)'))
    has_theme_mobile = [bool]([regex]::IsMatch($Html, '(?is)(?:mobile\.js)'))
    has_navigation_div = [bool]([regex]::IsMatch($Html, '(?is)<div id="navigation">'))
    has_navmobile_div = [bool]([regex]::IsMatch($Html, '(?is)<div id="navmobile"'))
    has_banner_wrap = [bool]([regex]::IsMatch($Html, '(?is)<div class="banner-wrap">'))
  }
}

$rows = New-Object System.Collections.Generic.List[object]
$fetched = 0
$liveErrors = 0
$visualMismatches = 0
$navDesktopMismatches = 0
$navMobileMismatches = 0
$titleMismatches = 0
$bodyClassMismatches = 0

$index = 0
$pageTotal = $pages.Count

foreach ($page in $pages) {
  $index++
  $legacy = [string]$page.legacy_path
  $canonical = [string]$page.canonical_path
  $localPath = Get-CanonicalPageOutputPath -Page $page

  if (-not (Test-Path -LiteralPath $localPath)) {
    $rows.Add([pscustomobject]@{
      legacy_path = $legacy
      canonical_path = $canonical
      live_status = 0
      local_exists = $false
      title_match = $false
      body_class_match = $false
      visual_structure_match = $false
      desktop_nav_match = $false
      mobile_nav_match = $false
      desktop_menu_text_match = $false
      mobile_menu_text_match = $false
      live_menu_signature = ""
      local_menu_signature = ""
      note = "Missing local canonical file"
    })
    continue
  }

  $localHtml = Read-TextFileSafe -Path $localPath
  $liveUrl = Get-LivePageUrl -LegacyPath $legacy
  Write-Host ("[{0}/{1}] Compare {2}" -f $index, $pageTotal, $liveUrl)
  $fetch = Invoke-PageFetch -Url $liveUrl
  $fetched++
  if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

  if ($fetch.status -ne 200 -or [string]::IsNullOrWhiteSpace($fetch.html)) {
    $liveErrors++
    $rows.Add([pscustomobject]@{
      legacy_path = $legacy
      canonical_path = $canonical
      live_status = $fetch.status
      local_exists = $true
      title_match = $false
      body_class_match = $false
      visual_structure_match = $false
      desktop_nav_match = $false
      mobile_nav_match = $false
      desktop_menu_text_match = $false
      mobile_menu_text_match = $false
      live_menu_signature = ""
      local_menu_signature = ""
      note = ("Live fetch failed: " + $fetch.error)
    })
    continue
  }

  $liveHtml = [string]$fetch.html

  $liveParts = Get-HtmlDocumentParts -Html $liveHtml
  $localParts = Get-HtmlDocumentParts -Html $localHtml

  $titleMatch = ([string]$liveParts.Title -eq [string]$localParts.Title)
  if (-not $titleMatch) { $titleMismatches++ }

  $liveBodyClass = Try-GetRegexMatchValue -Text ([string]$liveParts.BodyTagAttributes) -Pattern '\bclass\s*=\s*["'']([^"'']*)["'']'
  $localBodyClass = Try-GetRegexMatchValue -Text ([string]$localParts.BodyTagAttributes) -Pattern '\bclass\s*=\s*["'']([^"'']*)["'']'
  if ($null -eq $liveBodyClass) { $liveBodyClass = "" }
  if ($null -eq $localBodyClass) { $localBodyClass = "" }
  $liveBodyClassNorm = ([regex]::Replace($liveBodyClass, '\s+', ' ')).Trim()
  $localBodyClassNorm = ([regex]::Replace($localBodyClass, '\s+', ' ')).Trim()
  $bodyClassMatch = ($liveBodyClassNorm -eq $localBodyClassNorm)
  if (-not $bodyClassMatch) { $bodyClassMismatches++ }

  $liveDesktopNav = Extract-NavBlock -Html $liveHtml -Which desktop
  $localDesktopNav = Extract-NavBlock -Html $localHtml -Which desktop
  $liveMobileNav = Extract-NavBlock -Html $liveHtml -Which mobile
  $localMobileNav = Extract-NavBlock -Html $localHtml -Which mobile

  $liveDesktopNavNorm = Normalize-HtmlForVisualCompare -Html ([string]$liveDesktopNav)
  $localDesktopNavNorm = Normalize-HtmlForVisualCompare -Html ([string]$localDesktopNav)
  $liveMobileNavNorm = Normalize-HtmlForVisualCompare -Html ([string]$liveMobileNav)
  $localMobileNavNorm = Normalize-HtmlForVisualCompare -Html ([string]$localMobileNav)

  $desktopNavMatch = ($liveDesktopNavNorm -eq $localDesktopNavNorm)
  $mobileNavMatch = ($liveMobileNavNorm -eq $localMobileNavNorm)
  if (-not $desktopNavMatch) { $navDesktopMismatches++ }
  if (-not $mobileNavMatch) { $navMobileMismatches++ }

  $liveDesktopMenuSig = Get-MenuTextSignature -NavBlockHtml ([string]$liveDesktopNav)
  $localDesktopMenuSig = Get-MenuTextSignature -NavBlockHtml ([string]$localDesktopNav)
  $desktopMenuTextMatch = ($liveDesktopMenuSig -eq $localDesktopMenuSig)

  $liveMobileMenuSig = Get-MenuTextSignature -NavBlockHtml ([string]$liveMobileNav)
  $localMobileMenuSig = Get-MenuTextSignature -NavBlockHtml ([string]$localMobileNav)
  $mobileMenuTextMatch = ($liveMobileMenuSig -eq $localMobileMenuSig)

  # Compare body markup only for visual parity. Head markup intentionally differs
  # because local builds vendor CDN assets into repo paths.
  $liveVisualNorm = Normalize-HtmlForVisualCompare -Html ([string]$liveParts.BodyInner)
  $localVisualNorm = Normalize-HtmlForVisualCompare -Html ([string]$localParts.BodyInner)
  $visualMatch = ($liveVisualNorm -eq $localVisualNorm)
  if (-not $visualMatch) { $visualMismatches++ }

  $liveFlags = Get-ThemeAssetFlags -Html $liveHtml
  $localFlags = Get-ThemeAssetFlags -Html $localHtml

  $notes = New-Object System.Collections.Generic.List[string]
  if (-not $liveFlags.has_navigation_div -or -not $localFlags.has_navigation_div) { [void]$notes.Add("navigation div missing") }
  if (-not $liveFlags.has_banner_wrap -or -not $localFlags.has_banner_wrap) { [void]$notes.Add("banner-wrap missing") }
  if (-not $localFlags.has_main_style) { [void]$notes.Add("local main_style.css ref missing") }
  if (-not $localFlags.has_theme_plugins -or -not $localFlags.has_theme_custom -or -not $localFlags.has_theme_mobile) { [void]$notes.Add("local theme js refs missing") }

  $rows.Add([pscustomobject]@{
    legacy_path = $legacy
    canonical_path = $canonical
    live_status = $fetch.status
    local_exists = $true
    title_match = $titleMatch
    body_class_match = $bodyClassMatch
    visual_structure_match = $visualMatch
    desktop_nav_match = $desktopNavMatch
    mobile_nav_match = $mobileNavMatch
    desktop_menu_text_match = $desktopMenuTextMatch
    mobile_menu_text_match = $mobileMenuTextMatch
    live_visual_hash = (Get-StringSha256 -Text $liveVisualNorm)
    local_visual_hash = (Get-StringSha256 -Text $localVisualNorm)
    live_desktop_nav_hash = (Get-StringSha256 -Text $liveDesktopNavNorm)
    local_desktop_nav_hash = (Get-StringSha256 -Text $localDesktopNavNorm)
    live_mobile_nav_hash = (Get-StringSha256 -Text $liveMobileNavNorm)
    local_mobile_nav_hash = (Get-StringSha256 -Text $localMobileNavNorm)
    live_menu_signature = $liveDesktopMenuSig
    local_menu_signature = $localDesktopMenuSig
    note = ($notes -join "; ")
  })
}

$csvPath = Join-Path $migrationRoot "live-page-compare.csv"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$total = $rows.Count
$ok200 = @($rows | Where-Object { $_.live_status -eq 200 }).Count
$allGood = @($rows | Where-Object {
  $_.live_status -eq 200 -and
  $_.title_match -and
  $_.body_class_match -and
  $_.desktop_nav_match -and
  $_.mobile_nav_match -and
  $_.desktop_menu_text_match -and
  $_.mobile_menu_text_match -and
  $_.visual_structure_match
}).Count

$mismatchRows = @($rows | Where-Object {
  $_.live_status -ne 200 -or
  -not $_.title_match -or
  -not $_.body_class_match -or
  -not $_.desktop_nav_match -or
  -not $_.mobile_nav_match -or
  -not $_.desktop_menu_text_match -or
  -not $_.mobile_menu_text_match -or
  -not $_.visual_structure_match
})

$summaryLines = @(
  "Generated UTC: $([DateTime]::UtcNow.ToString('o'))",
  "Base URL: $BaseUrl",
  "Pages in manifest: $total",
  "Live fetches attempted: $fetched",
  "Live 200 responses: $ok200",
  "Live fetch failures/non-200: $liveErrors",
  "Title mismatches: $titleMismatches",
  "Body class mismatches: $bodyClassMismatches",
  "Desktop nav mismatches: $navDesktopMismatches",
  "Mobile nav mismatches: $navMobileMismatches",
  "Visual structure mismatches (normalized): $visualMismatches",
  "Pages fully matched on all checks: $allGood",
  "CSV report: $csvPath"
)
Write-LinesUtf8NoBom -Path (Join-Path $migrationRoot "live-page-compare-summary.txt") -Lines $summaryLines

$mdLines = New-Object System.Collections.Generic.List[string]
[void]$mdLines.Add("# Live vs Generated Page Compare")
[void]$mdLines.Add("")
[void]$mdLines.AddRange([string[]]($summaryLines | ForEach-Object { "- $_" }))
[void]$mdLines.Add("")
[void]$mdLines.Add("## Mismatch Samples")
[void]$mdLines.Add("")
if ($mismatchRows.Count -eq 0) {
  [void]$mdLines.Add("No mismatches detected.")
}
else {
  foreach ($r in ($mismatchRows | Select-Object -First 25)) {
    $checks = @()
    if (-not $r.title_match) { $checks += "title" }
    if (-not $r.body_class_match) { $checks += "body-class" }
    if (-not $r.desktop_nav_match) { $checks += "desktop-nav" }
    if (-not $r.mobile_nav_match) { $checks += "mobile-nav" }
    if (-not $r.desktop_menu_text_match) { $checks += "desktop-menu-text" }
    if (-not $r.mobile_menu_text_match) { $checks += "mobile-menu-text" }
    if (-not $r.visual_structure_match) { $checks += "visual-structure" }
    if ($r.live_status -ne 200) { $checks = @("live-status=" + $r.live_status) + $checks }
    [void]$mdLines.Add(("* `{0}` -> `{1}` : {2}" -f $r.legacy_path, $r.canonical_path, ($checks -join ", ")))
  }
}
Write-TextFileUtf8NoBom -Path (Join-Path $migrationRoot "live-page-compare.md") -Content (($mdLines.ToArray()) -join [Environment]::NewLine)

Write-Output ("Compared {0} pages against live site ({1} OK fetches). Visual mismatches: {2}. Desktop nav mismatches: {3}. Mobile nav mismatches: {4}." -f $total, $ok200, $visualMismatches, $navDesktopMismatches, $navMobileMismatches)
