param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SourceDocs = "docs-source",
  [string]$SiteSrc = "site-src",
  [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$sourceDocsPath = Join-Path $RepoRoot $SourceDocs
$vendorRoot = Join-Path (Join-Path $RepoRoot $SiteSrc) "static\assets\vendor\editmysite"
$dataRoot = Join-Path (Join-Path $RepoRoot $SiteSrc) "data"
$migrationRoot = Join-Path $RepoRoot "migration"
Ensure-Directory -Path $vendorRoot
Ensure-Directory -Path $dataRoot
Ensure-Directory -Path $migrationRoot

$htmlFiles = Get-ChildItem -LiteralPath $sourceDocsPath -Filter *.html -File
$urlSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$pattern = '(?is)(?:href|src)\s*=\s*["'']([^"'']+)["'']'

foreach ($f in $htmlFiles) {
  $html = Read-TextFileSafe -Path $f.FullName
  foreach ($m in [regex]::Matches($html, $pattern)) {
    $u = $m.Groups[1].Value
    if ($u -match '^https?://(?:cdn\d+\.editmysite\.com|cdn\d+\.weebly\.com|www\.weebly\.com)/') {
      [void]$urlSet.Add($u)
    }
  }
}

$queue = New-Object System.Collections.Generic.Queue[string]
foreach ($u in $urlSet) { $queue.Enqueue($u) }
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$rows = New-Object System.Collections.Generic.List[object]

function Get-LocalVendorPathForUrl {
  param([Parameter(Mandatory = $true)][uri]$Uri)
  $hostName = $Uri.Host.ToLowerInvariant()
  $path = $Uri.AbsolutePath.TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($path)) { $path = "index" }
  $targetRel = ("assets/vendor/editmysite/{0}/{1}" -f $hostName, $path).Replace("\", "/")
  $targetAbs = Join-Path (Join-Path $RepoRoot $SiteSrc) ("static\" + ($targetRel -replace "/", "\"))
  return [pscustomobject]@{
    Relative = $targetRel
    Absolute = $targetAbs
    UrlPath = "/" + $targetRel
  }
}

function Download-UrlToFile {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  Ensure-Directory -Path (Split-Path -Parent $Destination)
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing | Out-Null
    Copy-FilePreserveTimestamp -SourcePath $tmp -DestinationPath $Destination
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

while ($queue.Count -gt 0) {
  $url = $queue.Dequeue()
  if ($seen.Contains($url)) { continue }
  [void]$seen.Add($url)

  $uri = [uri]$url
  $destInfo = Get-LocalVendorPathForUrl -Uri $uri
  $downloaded = $false
  if (-not $SkipDownload) {
    if (-not (Test-Path -LiteralPath $destInfo.Absolute)) {
      Download-UrlToFile -Url $url -Destination $destInfo.Absolute
    }
    $downloaded = $true
  }

  $rows.Add([pscustomobject]@{
    external_url = $url
    local_url = $destInfo.UrlPath
    local_path = (Get-RelativePathUnix -Root $RepoRoot -Path $destInfo.Absolute)
    downloaded = $downloaded
  })

  if ($destInfo.Absolute.ToLowerInvariant().EndsWith(".css") -and (Test-Path -LiteralPath $destInfo.Absolute)) {
    $css = Read-TextFileSafe -Path $destInfo.Absolute
    foreach ($m in [regex]::Matches($css, '(?is)url\(([^)]+)\)')) {
      $raw = $m.Groups[1].Value.Trim().Trim("'").Trim('"')
      if ([string]::IsNullOrWhiteSpace($raw)) { continue }
      if ($raw -match '^(?:data:|https?://|//)') {
        if ($raw -match '^https?://(?:cdn\d+\.editmysite\.com|cdn\d+\.weebly\.com|www\.weebly\.com)/') {
          if (-not $seen.Contains($raw)) { $queue.Enqueue($raw) }
        }
        continue
      }
      try {
        $resolved = [uri]::new($uri, $raw).AbsoluteUri
        if ($resolved -match '^https?://(?:cdn\d+\.editmysite\.com|cdn\d+\.weebly\.com|www\.weebly\.com)/') {
          if (-not $seen.Contains($resolved)) { $queue.Enqueue($resolved) }
        }
      } catch {}
    }
  }
}

$rows | Sort-Object external_url | Export-Csv -LiteralPath (Join-Path $migrationRoot "vendor-external-url-map.csv") -NoTypeInformation -Encoding UTF8
($rows | Sort-Object external_url | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $dataRoot "vendor-url-map.json") -Encoding utf8
Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "vendor-url-map.yaml") -Items ($rows | Sort-Object external_url) -KeyOrder @("external_url","local_url","local_path","downloaded")

Write-Output "Vendored $($rows.Count) external Weebly/EditMySite assets."
