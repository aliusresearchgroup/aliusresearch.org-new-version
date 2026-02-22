param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SiteSrc = "site-src",
  [int]$GifThresholdMb = 0,
  [int]$MaxDimension = 1920,
  [switch]$ProcessAllGifs,
  [switch]$SkipBackup,
  [string]$BackupRoot = "C:\Users\cogpsy-vrlab\Proton Drive\George.Fejer\My files\aliusresearch.org-originals"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$migrationRoot = Join-Path $RepoRoot "migration"
Ensure-Directory -Path $migrationRoot
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue

function Get-ScaledDimensions {
  param(
    [int]$Width,
    [int]$Height,
    [int]$MaxDimension
  )
  if ($Width -le 0 -or $Height -le 0) {
    return @{ Width = $Width; Height = $Height }
  }
  $largest = [Math]::Max($Width, $Height)
  if ($largest -le $MaxDimension) {
    return @{ Width = $Width; Height = $Height }
  }
  $scale = [double]$MaxDimension / [double]$largest
  $newW = [Math]::Max(1, [int][Math]::Round($Width * $scale))
  $newH = [Math]::Max(1, [int][Math]::Round($Height * $scale))
  return @{ Width = $newW; Height = $newH }
}

function Convert-GifToStaticGif {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxDimension = 1920
  )

  Add-Type -AssemblyName System.Drawing
  $img = $null
  $bmp = $null
  $gfx = $null
  $tmpPath = $null
  try {
    $img = [System.Drawing.Image]::FromFile($Path)
    $dims = Get-ScaledDimensions -Width $img.Width -Height $img.Height -MaxDimension $MaxDimension
    $targetW = [int]$dims.Width
    $targetH = [int]$dims.Height
    $widthBefore = [int]$img.Width
    $heightBefore = [int]$img.Height

    $tmpPath = "$Path.tmp-static"
    if ($targetW -eq $img.Width -and $targetH -eq $img.Height) {
      # Save first frame as a single-frame static GIF at original dimensions.
      $bmp = New-Object System.Drawing.Bitmap $img.Width, $img.Height
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $gfx.DrawImage($img, 0, 0, $bmp.Width, $bmp.Height)
      $bmp.Save($tmpPath, [System.Drawing.Imaging.ImageFormat]::Gif)
    } else {
      $bmp = New-Object System.Drawing.Bitmap $targetW, $targetH
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $gfx.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $gfx.DrawImage($img, 0, 0, $targetW, $targetH)
      $bmp.Save($tmpPath, [System.Drawing.Imaging.ImageFormat]::Gif)
    }

    if ($gfx) { $gfx.Dispose(); $gfx = $null }
    if ($bmp) { $bmp.Dispose(); $bmp = $null }
    if ($img) { $img.Dispose(); $img = $null }

    [System.IO.File]::Copy((Get-LongPath -Path $tmpPath), (Get-LongPath -Path $Path), $true)
    Remove-Item -LiteralPath $tmpPath -Force
    return [pscustomobject]@{
      width_before = $widthBefore
      height_before = $heightBefore
      width_after = [int]$targetW
      height_after = [int]$targetH
    }
  } finally {
    if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
      try { Remove-Item -LiteralPath $tmpPath -Force } catch {}
    }
    if ($gfx) { $gfx.Dispose() }
    if ($bmp) { $bmp.Dispose() }
    if ($img) { $img.Dispose() }
  }
}

$gifRoots = @(
  (Join-Path $siteSrcPath "static\media\animations"),
  (Join-Path $siteSrcPath "static\media\images")
)
$gifFiles = @()
foreach ($gr in $gifRoots) {
  if (Test-Path -LiteralPath $gr) {
    $gifFiles += Get-ChildItem -LiteralPath $gr -Recurse -File -Filter *.gif
  }
}

if (-not $ProcessAllGifs) {
  $gifFiles = @($gifFiles | Where-Object { $_.Length -ge ($GifThresholdMb * 1MB) })
}

if (-not $SkipBackup) {
  Ensure-Directory -Path $BackupRoot
  Ensure-Directory -Path (Join-Path $BackupRoot "optimized-live-gif-originals")
}

$rows = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]
$processed = 0
$savedBytes = [int64]0

foreach ($gif in ($gifFiles | Sort-Object Length -Descending)) {
  $beforeBytes = [int64]$gif.Length
  $relFromStatic = Get-RelativePathUnix -Root (Join-Path $siteSrcPath "static") -Path $gif.FullName
  $backupRel = ""
  try {
    if (-not $SkipBackup) {
      $backupDest = Join-Path (Join-Path $BackupRoot "optimized-live-gif-originals") ($relFromStatic -replace "/", "\")
      if (-not (Test-Path -LiteralPath $backupDest)) {
        Copy-FilePreserveTimestamp -SourcePath $gif.FullName -DestinationPath $backupDest
      }
      $backupRel = Get-RelativePathUnix -Root $BackupRoot -Path $backupDest
    }

    $dimInfo = Convert-GifToStaticGif -Path $gif.FullName -MaxDimension $MaxDimension
    $afterBytes = [int64](Get-Item -LiteralPath $gif.FullName).Length
    $processed++
    $savedBytes += [Math]::Max(0, ($beforeBytes - $afterBytes))
    $rows.Add([pscustomobject]@{
      relative_path = ("static/" + $relFromStatic)
      bytes_before = $beforeBytes
      bytes_after = $afterBytes
      bytes_saved = [Math]::Max(0, ($beforeBytes - $afterBytes))
      width_before = $dimInfo.width_before
      height_before = $dimInfo.height_before
      width_after = $dimInfo.width_after
      height_after = $dimInfo.height_after
      backup_path = $backupRel
    })
  } catch {
    $errors.Add([pscustomobject]@{
      relative_path = ("static/" + $relFromStatic)
      bytes_before = $beforeBytes
      error = $_.Exception.Message
    })
  }
}

$rows | Sort-Object bytes_saved -Descending | Export-Csv -LiteralPath (Join-Path $migrationRoot "gif-static-optimization.csv") -NoTypeInformation -Encoding UTF8
if ($errors.Count -gt 0) {
  $errors | Export-Csv -LiteralPath (Join-Path $migrationRoot "gif-static-optimization-errors.csv") -NoTypeInformation -Encoding UTF8
}

$status = @(
  "Generated UTC: $([DateTime]::UtcNow.ToString('o'))",
  "ffmpeg_available: $([bool]($null -ne $ffmpeg))",
  "mode: static-gif-fallback (PowerShell/.NET first-frame replacement)",
  "gif_files_considered: $($gifFiles.Count)",
  "gif_files_processed: $processed",
  "gif_bytes_saved: $savedBytes",
  "gif_mb_saved: $([Math]::Round($savedBytes / 1MB, 2))",
  "max_dimension: $MaxDimension",
  "process_all_gifs: $([bool]$ProcessAllGifs)",
  "backup_enabled: $([bool](-not $SkipBackup))",
  "backup_root: $BackupRoot",
  "report_csv: migration/gif-static-optimization.csv"
)
if (-not $ffmpeg) {
  $status += "note: ffmpeg not found, so GIF->video conversion was not run. Static GIF fallback was applied instead."
} else {
  $status += "note: ffmpeg is available, but this script currently executed static GIF fallback only."
}
if ($errors.Count -gt 0) {
  $status += "errors: $($errors.Count) (see migration/gif-static-optimization-errors.csv)"
}
Write-LinesUtf8NoBom -Path (Join-Path $migrationRoot "media-optimization-status.txt") -Lines $status

Write-Output ("Static GIF optimization complete. Processed {0} GIFs. Saved {1} MB." -f $processed, ([Math]::Round($savedBytes / 1MB, 2)))
