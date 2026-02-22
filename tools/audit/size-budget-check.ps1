param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$DocsDir = "docs",
  [int]$LimitMb = 1024,
  [int]$TargetMb = 900
)

$docsPath = Join-Path $RepoRoot $DocsDir
if (-not (Test-Path -LiteralPath $docsPath)) { throw "Docs dir not found: $docsPath" }
$files = Get-ChildItem -LiteralPath $docsPath -Recurse -File
$bytes = ($files | Measure-Object Length -Sum).Sum
$mb = [math]::Round($bytes / 1MB, 2)
$limitBytes = $LimitMb * 1MB
$targetBytes = $TargetMb * 1MB

Write-Output ("Docs size: {0} MB ({1} bytes)" -f $mb, $bytes)
Write-Output ("Target: <= {0} MB" -f $TargetMb)
Write-Output ("Hard limit (GitHub Pages): <= {0} MB" -f $LimitMb)
if ($bytes -le $targetBytes) {
  Write-Output "PASS: under target size."
} elseif ($bytes -le $limitBytes) {
  Write-Warning "PASS (limit), but above target."
} else {
  Write-Error "FAIL: above GitHub Pages limit."
}

$files | ForEach-Object {
  [pscustomobject]@{
    ext = if([string]::IsNullOrEmpty($_.Extension)){"(none)"} else {$_.Extension.ToLowerInvariant()}
    bytes = [int64]$_.Length
  }
} | Group-Object ext | ForEach-Object {
  [pscustomobject]@{
    ext = $_.Name
    count = $_.Count
    bytes = ($_.Group | Measure-Object bytes -Sum).Sum
    mb = [math]::Round((($_.Group | Measure-Object bytes -Sum).Sum)/1MB,2)
  }
} | Sort-Object bytes -Descending | Format-Table -AutoSize
