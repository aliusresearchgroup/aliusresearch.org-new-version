param(
  [Parameter(Mandatory = $true)]
  [string]$RepoRoot,

  [Parameter(Mandatory = $true)]
  [string]$ZipPath,

  [string]$DeployDirName = "docs",
  [string]$MigrationDirName = "migration"
)

$ErrorActionPreference = "Stop"

function Get-LongPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ($Path.StartsWith("\\?\")) { return $Path }
  if ($Path.StartsWith("\\")) { return "\\?\UNC\" + $Path.TrimStart("\") }
  return "\\?\" + $Path
}

function Ensure-CleanDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
  [IO.Directory]::CreateDirectory((Get-LongPath -Path $Path)) | Out-Null
}

$repoRoot = [IO.Path]::GetFullPath($RepoRoot)
$zipPath = [IO.Path]::GetFullPath($ZipPath)
$deployPath = Join-Path $repoRoot $DeployDirName
$migrationPath = Join-Path $repoRoot $MigrationDirName

if (-not (Test-Path -LiteralPath $zipPath)) {
  throw "ZIP archive not found: $zipPath"
}

Ensure-CleanDirectory -Path $deployPath
Ensure-CleanDirectory -Path $migrationPath

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)

try {
  if ($zip.Entries.Count -eq 0) {
    throw "ZIP archive is empty."
  }

  $firstEntry = $zip.Entries | Where-Object { $_.FullName } | Select-Object -First 1
  $rootName = ($firstEntry.FullName -split "/")[0]
  if (-not $rootName) {
    throw "Could not determine top-level wrapper directory in ZIP."
  }
  $rootPrefix = "$rootName/"

  $manifestPath = Join-Path $migrationPath "weebly-zip-manifest.csv"
  $manifestWriter = [IO.StreamWriter]::new($manifestPath, $false, [Text.UTF8Encoding]::new($false))

  try {
    $manifestWriter.WriteLine("zip_path,relative_path,is_directory,length,last_write_time_utc")

    $fileCount = 0
    $dirCount = 0
    [int64]$totalBytes = 0

    foreach ($entry in $zip.Entries) {
      $zipFull = $entry.FullName

      if (-not $zipFull.StartsWith($rootPrefix, [StringComparison]::Ordinal)) {
        throw "Unexpected ZIP entry outside wrapper directory: $zipFull"
      }

      $relPath = $zipFull.Substring($rootPrefix.Length)
      if ([string]::IsNullOrEmpty($relPath)) {
        continue
      }

      $isDir = $zipFull.EndsWith("/")
      $relWindows = $relPath.Replace("/", [IO.Path]::DirectorySeparatorChar)
      $destPath = Join-Path $deployPath $relWindows
      $destLongPath = Get-LongPath -Path $destPath

      $csvZip = '"' + $zipFull.Replace('"', '""') + '"'
      $csvRel = '"' + $relPath.Replace('"', '""') + '"'
      $lastWriteUtc = [DateTime]::SpecifyKind($entry.LastWriteTime.UtcDateTime, [DateTimeKind]::Utc).ToString("o")
      $manifestWriter.WriteLine("$csvZip,$csvRel,$isDir,$($entry.Length),$lastWriteUtc")

      if ($isDir) {
        [IO.Directory]::CreateDirectory($destLongPath) | Out-Null
        try { [IO.Directory]::SetLastWriteTimeUtc($destLongPath, $entry.LastWriteTime.UtcDateTime) } catch {}
        $dirCount++
        continue
      }

      $parentPath = [IO.Path]::GetDirectoryName($destPath)
      if ($parentPath) {
        [IO.Directory]::CreateDirectory((Get-LongPath -Path $parentPath)) | Out-Null
      }

      $inStream = $entry.Open()
      try {
        $outStream = [IO.File]::Open($destLongPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
          $inStream.CopyTo($outStream)
        } finally {
          $outStream.Dispose()
        }
      } finally {
        $inStream.Dispose()
      }

      try { [IO.File]::SetLastWriteTimeUtc($destLongPath, $entry.LastWriteTime.UtcDateTime) } catch {}

      $fileCount++
      $totalBytes += $entry.Length
    }

    [IO.File]::WriteAllText((Get-LongPath -Path (Join-Path $deployPath ".nojekyll")), "", [Text.UTF8Encoding]::new($false))

    $summaryLines = @(
      "Extracted Weebly export into GitHub Pages deploy folder",
      "ZIP archive: $zipPath",
      "Stripped wrapper folder: $rootName",
      "Deploy path: $deployPath",
      "Files extracted: $fileCount",
      "Directories created: $dirCount",
      "Total file bytes: $totalBytes",
      "Generated UTC: $([DateTime]::UtcNow.ToString('o'))"
    )

    [IO.File]::WriteAllLines((Get-LongPath -Path (Join-Path $migrationPath "extraction-summary.txt")), $summaryLines, [Text.UTF8Encoding]::new($false))
    $summaryLines -join [Environment]::NewLine
  } finally {
    $manifestWriter.Dispose()
  }
} finally {
  $zip.Dispose()
}
