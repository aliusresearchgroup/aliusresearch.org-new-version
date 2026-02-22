param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SiteSrc = "site-src"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$dataRoot = Join-Path $siteSrcPath "data"
$contentRoot = Join-Path $siteSrcPath "content"
$migrationRoot = Join-Path $RepoRoot "migration"

$pages = Get-Content -LiteralPath (Join-Path $dataRoot "pages.json") -Raw | ConvertFrom-Json
$mediaMap = Get-Content -LiteralPath (Join-Path $dataRoot "media-map.json") -Raw | ConvertFrom-Json
$vendorMapPath = Join-Path $dataRoot "vendor-url-map.json"
$vendorMap = @()
if (Test-Path -LiteralPath $vendorMapPath) {
  $vendorMap = Get-Content -LiteralPath $vendorMapPath -Raw | ConvertFrom-Json
}

$legacyPageMap = @{}
foreach ($p in $pages) { $legacyPageMap[$p.legacy_path] = [string]$p.canonical_path }

$assetMap = @{}
foreach ($a in $mediaMap) {
  if (-not [string]::IsNullOrWhiteSpace([string]$a.canonical_path)) {
    $assetMap[[string]$a.legacy_path] = [string]$a.canonical_path
  }
}

$vendorUrlMap = @{}
foreach ($v in $vendorMap) {
  $vendorUrlMap[[string]$v.external_url] = [string]$v.local_url
}

function Get-NormalizedLookupVariants {
  param([Parameter(Mandatory = $true)][string]$Path)

  $variants = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  function Add-Variant([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return }
    $v = $v.Replace("\", "/")
    $v = $v -replace '^\./+', ''
    $v = $v.Trim()
    if ($v.StartsWith("/")) { $v = $v.Substring(1) }
    if ([string]::IsNullOrWhiteSpace($v)) { return }
    if ($seen.Add($v)) { [void]$variants.Add($v) }
  }

  Add-Variant $Path
  try { Add-Variant ([uri]::UnescapeDataString($Path)) } catch {}

  # Weebly export often references uploads/.../published/... and uploads/.../editor/... aliases
  foreach ($seed in @($variants.ToArray())) {
    Add-Variant ($seed -replace '/(?:published|editor)/', '/')
  }

  # Theme shortcuts in HTML often omit the extra "/files" folder that exists in the export.
  foreach ($seed in @($variants.ToArray())) {
    if ($seed -match '^files/theme/(?!files/)') {
      Add-Variant ($seed -replace '^files/theme/', 'files/theme/files/')
    }
  }

  return $variants.ToArray()
}

function Resolve-LocalUrlPath {
  param([Parameter(Mandatory = $true)][string]$OriginalPath)

  foreach ($candidate in (Get-NormalizedLookupVariants -Path $OriginalPath)) {
    if ($assetMap.ContainsKey($candidate)) {
      return [string]$assetMap[$candidate]
    }
  }

  return $null
}

function Rewrite-UrlToken {
  param([Parameter(Mandatory = $true)][string]$Token)

  if ([string]::IsNullOrWhiteSpace($Token)) { return $Token }
  $trimmed = $Token.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return $Token }

  # Preserve original quote style/spacing handled by regex; only return rewritten URL token.
  if ($trimmed -match '^(?:https?:|//|data:|mailto:|tel:|javascript:|#)') {
    return $trimmed
  }

  $base = $trimmed
  $suffix = ""
  $qIdx = $trimmed.IndexOf("?")
  $hIdx = $trimmed.IndexOf("#")
  $cutIdx = -1
  if ($qIdx -ge 0 -and $hIdx -ge 0) { $cutIdx = [Math]::Min($qIdx, $hIdx) }
  elseif ($qIdx -ge 0) { $cutIdx = $qIdx }
  elseif ($hIdx -ge 0) { $cutIdx = $hIdx }
  if ($cutIdx -ge 0) {
    $base = $trimmed.Substring(0, $cutIdx)
    $suffix = $trimmed.Substring($cutIdx)
  }

  # Root-relative and page-relative legacy html links
  $pageLookup = $base.TrimStart("/")
  if ($legacyPageMap.ContainsKey($pageLookup)) {
    return ([string]$legacyPageMap[$pageLookup]) + $suffix
  }

  $resolved = Resolve-LocalUrlPath -OriginalPath $base
  if ($null -ne $resolved) {
    return ([string]$resolved) + $suffix
  }

  # When pages move into nested folders, Weebly-style relative asset paths like
  # "uploads/..." break. Keep them site-root-relative even if we do not have a
  # canonical remap for the asset yet.
  if ($base -match '^(?:uploads|files|apps|cdn-cgi|gdpr)/') {
    return ("/" + $base.TrimStart("/")) + $suffix
  }

  return $trimmed
}

function Rewrite-HtmlText {
  param([Parameter(Mandatory = $true)][string]$Html)

  $out = $Html

  foreach ($kv in $vendorUrlMap.GetEnumerator()) {
    $out = $out.Replace($kv.Key, $kv.Value)
    $https = ($kv.Key -replace '^http://', 'https://')
    $out = $out.Replace($https, $kv.Value)
  }

  # Rewrite attribute URLs (href/src)
  $out = [regex]::Replace(
    $out,
    '(?is)\b(?<attr>href|src)\s*=\s*(?<q>["''])(?<url>[^"'']+)(?<q2>["''])',
    {
      param($m)
      $newUrl = Rewrite-UrlToken -Token $m.Groups['url'].Value
      return ($m.Groups['attr'].Value + "=" + $m.Groups['q'].Value + $newUrl + $m.Groups['q2'].Value)
    }
  )

  # Rewrite CSS url(...) tokens (quoted or unquoted)
  $out = [regex]::Replace(
    $out,
    '(?is)url\(\s*(?<q>["'']?)(?<url>[^)''""]+)(?<q2>["'']?)\s*\)',
    {
      param($m)
      $newUrl = Rewrite-UrlToken -Token $m.Groups['url'].Value
      $q1 = $m.Groups['q'].Value
      $q2 = $m.Groups['q2'].Value
      if ([string]::IsNullOrEmpty($q1) -and -not [string]::IsNullOrEmpty($q2)) { $q1 = $q2 }
      if ([string]::IsNullOrEmpty($q2) -and -not [string]::IsNullOrEmpty($q1)) { $q2 = $q1 }
      return ("url(" + $q1 + $newUrl + $q2 + ")")
    }
  )

  $out = $out.Replace("http://cdn11.editmysite.com", "https://cdn11.editmysite.com")
  $out = $out.Replace("http://cdn2.editmysite.com", "https://cdn2.editmysite.com")
  $out = $out.Replace("http://www.youtube.com/embed/", "https://www.youtube.com/embed/")

  return $out
}

$rewrittenRows = New-Object System.Collections.Generic.List[object]

foreach ($page in $pages) {
  $sourceRel = [string]$page.source_html
  $sourceAbs = Join-Path $siteSrcPath ($sourceRel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $sourceAbs)) { continue }
  $html = Read-TextFileSafe -Path $sourceAbs
  $rewritten = Rewrite-HtmlText -Html $html
  $outPath = [System.IO.Path]::ChangeExtension($sourceAbs, ".rewritten.html")
  Write-TextFileUtf8NoBom -Path $outPath -Content $rewritten
  $rewrittenRows.Add([pscustomobject]@{
    legacy_path = $page.legacy_path
    canonical_path = $page.canonical_path
    source_html = $sourceRel
    rewritten_html = (Get-RelativePathUnix -Root $siteSrcPath -Path $outPath)
  })
}

$rewrittenRows | Export-Csv -LiteralPath (Join-Path $migrationRoot "rewritten-page-sources.csv") -NoTypeInformation -Encoding UTF8
Write-Output "Rewrote links for $($rewrittenRows.Count) page sources."
