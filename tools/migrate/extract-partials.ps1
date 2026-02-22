param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SourceDocs = "docs-source",
  [string]$SiteSrc = "site-src"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$sourceDocsPath = Join-Path $RepoRoot $SourceDocs
$partialsRoot = Join-Path (Join-Path $RepoRoot $SiteSrc) "partials"
$migrationRoot = Join-Path $RepoRoot "migration"
Ensure-Directory -Path $partialsRoot
Ensure-Directory -Path $migrationRoot

$htmlFiles = Get-ChildItem -LiteralPath $sourceDocsPath -Filter *.html -File | Sort-Object Name
if ($htmlFiles.Count -eq 0) { throw "No HTML files found in $sourceDocsPath" }

$styleGroups = @{}
$scriptGroups = @{}
$footerGroups = @{}
$mobileNavGroups = @{}
$desktopNavGroups = @{}
$assetRefCounts = @{}

function Add-HashedBlock {
  param(
    [hashtable]$Table,
    [string]$Block
  )
  if ([string]::IsNullOrWhiteSpace($Block)) { return }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Block)))).Replace("-", "")
  } finally {
    $sha.Dispose()
  }
  if ($Table.ContainsKey($hash)) {
    $Table[$hash].Count++
  } else {
    $Table[$hash] = [pscustomobject]@{
      Hash = $hash
      Count = 1
      Bytes = [System.Text.Encoding]::UTF8.GetByteCount($Block)
      Block = $Block
    }
  }
}

foreach ($f in $htmlFiles) {
  $html = Read-TextFileSafe -Path $f.FullName

  foreach ($m in [regex]::Matches($html, '(?is)<style\b[^>]*>.*?</style>')) {
    Add-HashedBlock -Table $styleGroups -Block $m.Value
  }
  foreach ($m in [regex]::Matches($html, '(?is)<script(?![^>]*\bsrc=)[^>]*>.*?</script>')) {
    Add-HashedBlock -Table $scriptGroups -Block $m.Value
  }

  $footer = Try-GetRegexMatchValue -Text $html -Pattern '<div id="footer-content">(.*?)</div>\s*</div>\s*</div>'
  if ($null -ne $footer) { Add-HashedBlock -Table $footerGroups -Block $footer }

  $mobileNav = Try-GetRegexMatchValue -Text $html -Pattern '<div id="navmobile" class="nav">(.*?)</div>\s*</div>\s*</div>'
  if ($null -ne $mobileNav) { Add-HashedBlock -Table $mobileNavGroups -Block $mobileNav }

  $desktopNav = Try-GetRegexMatchValue -Text $html -Pattern '<div id="navigation">(.*?)</div>\s*</div>\s*</div>'
  if ($null -ne $desktopNav) { Add-HashedBlock -Table $desktopNavGroups -Block $desktopNav }

  foreach ($m in [regex]::Matches($html, '(?is)<(?:link|script)[^>]+(?:href|src)=["'']([^"'']+)["'']')) {
    $u = $m.Groups[1].Value
    if ($assetRefCounts.ContainsKey($u)) { $assetRefCounts[$u]++ } else { $assetRefCounts[$u] = 1 }
  }
}

$allStyle = $styleGroups.GetEnumerator() | ForEach-Object { $_.Value }
$allScript = $scriptGroups.GetEnumerator() | ForEach-Object { $_.Value }
$commonStyles = $allStyle | Where-Object { $_.Count -eq $htmlFiles.Count } | Sort-Object Bytes -Descending
$commonScripts = $allScript | Where-Object { $_.Count -eq $htmlFiles.Count } | Sort-Object Bytes -Descending

$footerWinner = $footerGroups.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object -Property @(
  @{ Expression = { $_.Count }; Descending = $true },
  @{ Expression = { $_.Bytes }; Descending = $true }
) | Select-Object -First 1
$mobileNavWinner = $mobileNavGroups.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object -Property @(
  @{ Expression = { $_.Count }; Descending = $true },
  @{ Expression = { $_.Bytes }; Descending = $true }
) | Select-Object -First 1
$desktopNavWinner = $desktopNavGroups.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object -Property @(
  @{ Expression = { $_.Count }; Descending = $true },
  @{ Expression = { $_.Bytes }; Descending = $true }
) | Select-Object -First 1

if ($footerWinner) {
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "footer.raw.html") -Content $footerWinner.Block
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "footer.njk") -Content "{{ footer_html | safe }}"
}
if ($mobileNavWinner) {
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "nav-mobile.raw.html") -Content $mobileNavWinner.Block
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "nav-mobile.njk") -Content "{{ mobile_nav_html | safe }}"
}
if ($desktopNavWinner) {
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "nav-desktop.raw.html") -Content $desktopNavWinner.Block
  Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "nav-desktop.njk") -Content "{{ desktop_nav_html | safe }}"
}

$stylePartialContent = ($commonStyles | ForEach-Object { $_.Block }) -join [Environment]::NewLine
$scriptPartialContent = ($commonScripts | ForEach-Object { $_.Block }) -join [Environment]::NewLine
Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "head-common-styles.raw.html") -Content $stylePartialContent
Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "weebly-compat-scripts.raw.html") -Content $scriptPartialContent
Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "head.njk") -Content @'
{{ page_head_before_common | safe }}
{{ head_common_styles | safe }}
{{ page_head_after_common | safe }}
'@
Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "weebly-compat-scripts.njk") -Content "{{ common_inline_scripts | safe }}"
Write-TextFileUtf8NoBom -Path (Join-Path $partialsRoot "video-loop.njk") -Content @'
<video autoplay muted loop playsinline preload="metadata" poster="{{ poster_url }}">
  {% if webm_url %}<source src="{{ webm_url }}" type="video/webm">{% endif %}
  {% if mp4_url %}<source src="{{ mp4_url }}" type="video/mp4">{% endif %}
</video>
<noscript><img src="{{ poster_url }}" alt="{{ alt | default('') }}"></noscript>
'@

$summaryPath = Join-Path $migrationRoot "partials-extraction-summary.txt"
$lines = @(
  "HTML pages scanned: $($htmlFiles.Count)",
  "Common style blocks (present on all pages): $($commonStyles.Count)",
  "Common script blocks (present on all pages): $($commonScripts.Count)",
  "Footer variants: $($footerGroups.Count); dominant footer pages: $(if ($footerWinner) { $footerWinner.Count } else { 0 })",
  "Mobile nav variants: $($mobileNavGroups.Count); dominant mobile nav pages: $(if ($mobileNavWinner) { $mobileNavWinner.Count } else { 0 })",
  "Desktop nav variants: $($desktopNavGroups.Count); dominant desktop nav pages: $(if ($desktopNavWinner) { $desktopNavWinner.Count } else { 0 })"
)
Write-LinesUtf8NoBom -Path $summaryPath -Lines $lines

$commonRefRows = $assetRefCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object @{n="count";e={$_.Value}}, @{n="url";e={$_.Key}}
$commonRefRows | Export-Csv -LiteralPath (Join-Path $migrationRoot "common-external-refs.csv") -NoTypeInformation -Encoding UTF8

Write-Output "Extracted partial candidates to $partialsRoot"
Write-Output "Wrote summary: $summaryPath"
