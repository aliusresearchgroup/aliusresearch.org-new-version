param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsDir = "docs-source"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\migrate\Migration.Common.ps1")

$docsPath = Join-Path $RepoRoot $DocsDir
if (-not (Test-Path -LiteralPath $docsPath)) { throw "Docs dir not found: $docsPath" }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in Get-ChildItem -LiteralPath $docsPath -Recurse -File) {
  $rel = Get-RelativePathUnix -Root $docsPath -Path $f.FullName
  $rows.Add([pscustomobject]@{
    hash = Get-FileSha256 -Path $f.FullName
    bytes = [int64]$f.Length
    path = $rel
    ext = if([string]::IsNullOrEmpty($f.Extension)){"(none)"} else {$f.Extension.ToLowerInvariant()}
  })
}

$groups = $rows | Group-Object hash | Where-Object { $_.Count -gt 1 }
$report = $groups | ForEach-Object {
  $size = [int64]$_.Group[0].bytes
  [pscustomobject]@{
    copies = $_.Count
    bytes_each = $size
    wasted_bytes = $size * ($_.Count - 1)
    ext = $_.Group[0].ext
    example = $_.Group[0].path
  }
} | Sort-Object wasted_bytes -Descending

$reportCsv = Join-Path $RepoRoot "migration\redundancy-audit.csv"
$report | Export-Csv -LiteralPath $reportCsv -NoTypeInformation -Encoding UTF8
Write-Output "Wrote redundancy report: $reportCsv"
Write-Output ("Potential exact duplicate savings: {0} bytes" -f (($report | Measure-Object wasted_bytes -Sum).Sum))
