param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsDir = "docs"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\migrate\Migration.Common.ps1")

$docsPath = Join-Path $RepoRoot $DocsDir
if (-not (Test-Path -LiteralPath $docsPath)) { throw "Docs dir not found: $docsPath" }

$allDocFiles = Get-ChildItem -LiteralPath $docsPath -Recurse -File
$docPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($f in $allDocFiles) {
  try {
    [void]$docPathSet.Add((Get-RelativePathUnix -Root $docsPath -Path $f.FullName))
  } catch {}
}

$pages = Get-ChildItem -LiteralPath $docsPath -Recurse -Filter *.html -File
$issues = New-Object System.Collections.Generic.List[object]

foreach ($page in $pages) {
  $html = Read-TextFileSafe -Path $page.FullName
  foreach ($m in [regex]::Matches($html, '(?is)(?:href|src)\s*=\s*["'']([^"'']+)["'']')) {
    $u = $m.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($u)) { continue }
    if ($u -match '^(?:https?:|//|data:|mailto:|tel:|javascript:|#)') { continue }
    if ($u -match '^\$\{[^}]+\}$') { continue }
    if ($u -match '^(?:YOUR_LINK_URL_HERE|path/to/|api/placeholder/)') { continue }
    $pathPart = ($u -split '[?#]',2)[0]
    if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
    $relCheck = $null
    if ($pathPart.StartsWith("/")) {
      $checkPath = Join-Path $docsPath ($pathPart.TrimStart("/") -replace "/", "\")
      $relCheck = $pathPart.TrimStart("/")
    } else {
      $checkPath = Join-Path (Split-Path -Parent $page.FullName) ($pathPart -replace "/", "\")
      try {
        $relCheck = Get-RelativePathUnix -Root $docsPath -Path $checkPath
      } catch {
        $relCheck = $null
      }
    }
    $exists = $false
    if ($relCheck -and $docPathSet.Contains($relCheck)) {
      $exists = $true
    }
    if (-not $exists) {
      try {
        $exists = (Test-Path -LiteralPath $checkPath)
      } catch {
        try {
          $lp = Get-LongPath -Path $checkPath
          $exists = [System.IO.File]::Exists($lp) -or [System.IO.Directory]::Exists($lp)
        } catch {
          $exists = $false
        }
      }
    }
    if (-not $exists) {
      $missingRel = $checkPath
      try { $missingRel = Get-RelativePathUnix -Root $RepoRoot -Path $checkPath } catch {}
      $issues.Add([pscustomobject]@{
        page = (Get-RelativePathUnix -Root $docsPath -Path $page.FullName)
        url = $u
        missing = $missingRel
      })
    }
  }
}

$issuesCsv = Join-Path $RepoRoot "migration\link-check-issues.csv"
$issues | Export-Csv -LiteralPath $issuesCsv -NoTypeInformation -Encoding UTF8
Write-Output "Checked $($pages.Count) HTML files."
Write-Output "Missing local links/assets found: $($issues.Count)"
Write-Output "Report: $issuesCsv"
