param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsOut = "docs",
  [string]$SiteSrc = "site-src",
  [string]$LinkCheckReport = "migration/link-check-issues.csv",
  [string]$BaseUrl = "https://www.aliusresearch.org",
  [switch]$SkipExisting
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$docsRoot = Join-Path $RepoRoot $DocsOut
$siteStaticRoot = Join-Path (Join-Path $RepoRoot $SiteSrc) "static"
$reportPath = Join-Path $RepoRoot $LinkCheckReport
$migrationRoot = Join-Path $RepoRoot "migration"

if (-not (Test-Path -LiteralPath $reportPath)) {
  throw "Link check report not found: $reportPath"
}

Ensure-Directory -Path $migrationRoot
Ensure-Directory -Path $docsRoot
Ensure-Directory -Path $siteStaticRoot

$rows = Import-Csv -LiteralPath $reportPath

function Test-SkippableUrl {
  param([string]$Url)

  if ([string]::IsNullOrWhiteSpace($Url)) { return $true }
  $u = $Url.Trim()
  if ($u.StartsWith('${')) { return $true }
  if ($u -eq 'YOUR_LINK_URL_HERE') { return $true }
  if ($u -match '^(?:data:|mailto:|tel:|javascript:|#)') { return $true }
  if ($u -match '^(?:api/placeholder/|path/to/)') { return $true }
  return $false
}

function Get-NormalizedLivePath {
  param([string]$Url)

  $u = $Url.Trim()
  if ($u -match '^https?://') {
    try {
      $uri = [Uri]$u
      return ($uri.AbsolutePath + $uri.Query)
    } catch {
      return $null
    }
  }

  if ($u.StartsWith("//")) {
    return ("https:" + $u)
  }

  # Treat remaining URLs as site-root relative for live fetching.
  if (-not $u.StartsWith("/")) {
    $u = "/" + $u
  }

  return $u
}

function Get-PathWithoutQuery {
  param([string]$UrlOrPath)
  $v = $UrlOrPath
  $hashIndex = $v.IndexOf('#')
  if ($hashIndex -ge 0) { $v = $v.Substring(0, $hashIndex) }
  $qIndex = $v.IndexOf('?')
  if ($qIndex -ge 0) { $v = $v.Substring(0, $qIndex) }
  return $v
}

function Is-ProbablyStaticAssetPath {
  param([string]$PathNoQuery)

  if ([string]::IsNullOrWhiteSpace($PathNoQuery)) { return $false }
  $p = $PathNoQuery.Trim()
  if (-not $p.StartsWith("/")) { return $false }
  if ($p -notmatch '^/(?:uploads|gdpr|cdn-cgi|media|files|apps)/') { return $false }

  $ext = [IO.Path]::GetExtension($p).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($ext)) { return $false }

  return $true
}

$uniqueTargets = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($row in $rows) {
  $url = [string]$row.url
  if (Test-SkippableUrl -Url $url) { continue }

  $normalized = Get-NormalizedLivePath -Url $url
  if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

  if ($normalized -match '^https?://') {
    # Only fetch from the live site host in this script.
    try {
      $uri = [Uri]$normalized
      if ($uri.Host -notin @('www.aliusresearch.org','aliusresearch.org')) { continue }
      $relativeWithQuery = $uri.PathAndQuery
    } catch {
      continue
    }
  } else {
    $relativeWithQuery = $normalized
  }

  $pathNoQuery = Get-PathWithoutQuery -UrlOrPath $relativeWithQuery
  if (-not (Is-ProbablyStaticAssetPath -PathNoQuery $pathNoQuery)) { continue }

  if (-not $uniqueTargets.ContainsKey($pathNoQuery)) {
    $uniqueTargets[$pathNoQuery] = $relativeWithQuery
  }
}

$resultRows = New-Object System.Collections.Generic.List[object]
$ok = 0
$failed = 0
$skipped = 0

foreach ($kvp in $uniqueTargets.GetEnumerator() | Sort-Object Key) {
  $pathNoQuery = [string]$kvp.Key
  $fetchPath = [string]$kvp.Value

  $relativeFs = $pathNoQuery.TrimStart("/") -replace "/", "\"
  $docsDest = Join-Path $docsRoot $relativeFs
  $staticDest = Join-Path $siteStaticRoot $relativeFs

  if ($SkipExisting -and (Test-Path -LiteralPath $docsDest) -and (Test-Path -LiteralPath $staticDest)) {
    $skipped++
    $resultRows.Add([pscustomobject]@{
      url = $fetchPath
      path = $pathNoQuery
      status = "skipped-existing"
      bytes = 0
      docs_path = (Get-RelativePathUnix -Root $RepoRoot -Path $docsDest)
      static_path = (Get-RelativePathUnix -Root $RepoRoot -Path $staticDest)
      note = ""
    })
    continue
  }

  $fetchUrl = if ($fetchPath -match '^https?://') { $fetchPath } else { ($BaseUrl.TrimEnd("/") + $fetchPath) }
  $tempPath = [IO.Path]::GetTempFileName()
  try {
    Write-Host "Fetching $fetchUrl"
    Invoke-WebRequest -Uri $fetchUrl -OutFile $tempPath -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'; 'Referer' = $BaseUrl } | Out-Null

    $fileInfo = Get-Item -LiteralPath $tempPath
    if ($fileInfo.Length -eq 0) {
      throw "Downloaded empty response"
    }

    $lowerExt = [IO.Path]::GetExtension($pathNoQuery).ToLowerInvariant()
    if ($lowerExt -notin @('.html','.htm','.js','.css','.json','.xml','.svg','.txt')) {
      $firstBytes = New-Object byte[] 16
      $fs = [IO.File]::OpenRead($tempPath)
      try {
        [void]$fs.Read($firstBytes, 0, $firstBytes.Length)
      } finally {
        $fs.Dispose()
      }
      $prefix = [Text.Encoding]::ASCII.GetString($firstBytes)
      if ($prefix -match '^\s*<(?:!DOCTYPE|html|HTML)') {
        throw "Received HTML content for non-HTML asset"
      }
    }

    Copy-FilePreserveTimestamp -SourcePath $tempPath -DestinationPath $docsDest
    Copy-FilePreserveTimestamp -SourcePath $tempPath -DestinationPath $staticDest

    $ok++
    $resultRows.Add([pscustomobject]@{
      url = $fetchPath
      path = $pathNoQuery
      status = "downloaded"
      bytes = $fileInfo.Length
      docs_path = (Get-RelativePathUnix -Root $RepoRoot -Path $docsDest)
      static_path = (Get-RelativePathUnix -Root $RepoRoot -Path $staticDest)
      note = ""
    })
  }
  catch {
    $failed++
    $resultRows.Add([pscustomobject]@{
      url = $fetchPath
      path = $pathNoQuery
      status = "failed"
      bytes = 0
      docs_path = ""
      static_path = ""
      note = $_.Exception.Message
    })
  }
  finally {
    try { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue } catch {}
  }
}

$resultCsv = Join-Path $migrationRoot "live-missing-fetch-results.csv"
$resultRows | Export-Csv -LiteralPath $resultCsv -NoTypeInformation -Encoding UTF8

$summaryLines = @(
  "Generated UTC: $([DateTime]::UtcNow.ToString('o'))",
  "Base URL: $BaseUrl",
  "Input report: $reportPath",
  "Candidate unique assets: $($uniqueTargets.Count)",
  "Downloaded: $ok",
  "Skipped existing: $skipped",
  "Failed: $failed",
  "Results CSV: $resultCsv"
)
Write-LinesUtf8NoBom -Path (Join-Path $migrationRoot "live-missing-fetch-summary.txt") -Lines $summaryLines

Write-Output "Fetched missing live assets: downloaded=$ok skipped=$skipped failed=$failed (candidates=$($uniqueTargets.Count))"
