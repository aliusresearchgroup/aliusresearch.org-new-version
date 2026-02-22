param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
  [string]$SourceDocs = "docs-source",
  [string]$SiteSrc = "site-src",
  [string]$BackupRoot = "C:\Users\cogpsy-vrlab\Proton Drive\George.Fejer\My files\aliusresearch.org-originals",
  [switch]$SkipBackup,
  [switch]$CleanGenerated
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "Migration.Common.ps1")

$sourceDocsPath = Join-Path $RepoRoot $SourceDocs
$siteSrcPath = Join-Path $RepoRoot $SiteSrc
$staticRoot = Join-Path $siteSrcPath "static"
$dataRoot = Join-Path $siteSrcPath "data"
$migrationRoot = Join-Path $RepoRoot "migration"

Ensure-Directory -Path $staticRoot
Ensure-Directory -Path (Join-Path $staticRoot "assets\vendor\weebly-site")
Ensure-Directory -Path (Join-Path $staticRoot "media\images")
Ensure-Directory -Path (Join-Path $staticRoot "media\animations")
Ensure-Directory -Path (Join-Path $staticRoot "media\audio")
Ensure-Directory -Path (Join-Path $staticRoot "library\pdfs")
Ensure-Directory -Path $migrationRoot
Ensure-Directory -Path $dataRoot

if ($CleanGenerated) {
  $generatedDirs = @(
    (Join-Path $staticRoot "media"),
    (Join-Path $staticRoot "library"),
    (Join-Path $staticRoot "assets\vendor\weebly-site")
  )
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  foreach ($gd in $generatedDirs) {
    if (Test-Path -LiteralPath $gd) {
      try {
        $leaf = Split-Path -Leaf $gd
        $parent = Split-Path -Parent $gd
        Rename-Item -LiteralPath $gd -NewName ($leaf + ".prev-" + $stamp)
      } catch {
        Write-Warning "Could not rename generated dir for cleanup: $gd. $_"
      }
    }
  }
  Ensure-Directory -Path (Join-Path $staticRoot "assets\vendor\weebly-site")
  Ensure-Directory -Path (Join-Path $staticRoot "media\images")
  Ensure-Directory -Path (Join-Path $staticRoot "media\animations")
  Ensure-Directory -Path (Join-Path $staticRoot "media\audio")
  Ensure-Directory -Path (Join-Path $staticRoot "library\pdfs")
}

if (-not $SkipBackup) {
  Ensure-Directory -Path $BackupRoot
  Ensure-Directory -Path (Join-Path $BackupRoot "uploads")
  Ensure-Directory -Path (Join-Path $BackupRoot "removed-duplicates")
  Ensure-Directory -Path (Join-Path $BackupRoot "removed-unreferenced")
  Ensure-Directory -Path (Join-Path $BackupRoot "manifests")
}

$textExtensions = @(".html", ".css", ".js", ".json")
$textCorpusFiles = Get-ChildItem -LiteralPath $sourceDocsPath -Recurse -File | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }
$localRefSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($tf in $textCorpusFiles) {
  $txt = Read-TextFileSafe -Path $tf.FullName
  $set = Get-LocalUrlCandidatesFromText -Text $txt
  foreach ($k in $set) { [void]$localRefSet.Add($k) }
}

function Add-ReferenceAliasVariants {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.Generic.HashSet[string]]$Set
  )

  $toAdd = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($ref in @($Set)) {
    if ([string]::IsNullOrWhiteSpace($ref)) { continue }
    $path = ($ref -split '[?#]', 2)[0].Trim().Replace("\", "/")
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($path.StartsWith("/")) { $path = $path.TrimStart("/") }
    if ([string]::IsNullOrWhiteSpace($path)) { continue }

    [void]$toAdd.Add($path)
    try { [void]$toAdd.Add([uri]::UnescapeDataString($path)) } catch {}

    if ($path -match '/(?:published|editor)/') {
      [void]$toAdd.Add(($path -replace '/(?:published|editor)/', '/'))
    }

    if ($path -match '^files/theme/(?!files/)') {
      [void]$toAdd.Add(($path -replace '^files/theme/', 'files/theme/files/'))
    }
  }

  foreach ($v in $toAdd) { [void]$Set.Add($v) }
}

Add-ReferenceAliasVariants -Set $localRefSet

function New-UniqueName {
  param(
    [Parameter(Mandatory = $true)][string]$DirectoryPath,
    [Parameter(Mandatory = $true)][string]$BaseName,
    [Parameter(Mandatory = $true)][string]$Extension
  )
  $safe = ConvertTo-Slug -Text $BaseName
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "asset" }
  $candidate = "$safe$Extension"
  $i = 1
  while (Test-Path -LiteralPath (Join-Path $DirectoryPath $candidate)) {
    $candidate = "$safe-$i$Extension"
    $i++
  }
  return $candidate
}

$allFiles = Get-ChildItem -LiteralPath $sourceDocsPath -Recurse -File | Sort-Object FullName
$assetFiles = foreach ($f in $allFiles) {
  if ($f.Name -eq ".nojekyll") { continue }
  $relTmp = Get-RelativePathUnix -Root $sourceDocsPath -Path $f.FullName
  $isSiteVendorPath = $relTmp.StartsWith("files/") -or $relTmp.StartsWith("apps/")
  $isText = $textExtensions -contains $f.Extension.ToLowerInvariant()
  if ($isSiteVendorPath -or -not $isText) { $f }
}

$assetRows = New-Object System.Collections.Generic.List[object]
foreach ($f in $assetFiles) {
  $rel = Get-RelativePathUnix -Root $sourceDocsPath -Path $f.FullName
  $ext = $f.Extension.ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($ext)) { $ext = "(none)" }
  $isReferenced = $localRefSet.Contains($rel) -or $localRefSet.Contains("/$rel")
  $hash = Get-FileSha256 -Path $f.FullName
  $assetRows.Add([pscustomobject]@{
    source_path = $f.FullName
    legacy_path = $rel
    extension = $ext
    bytes = [int64]$f.Length
    hash = $hash
    referenced = [bool]$isReferenced
    category = Get-AssetCategory -RelativePath $rel -Extension $ext -Bytes ([int64]$f.Length)
  })
}

function Get-NormalizedStem {
  param([Parameter(Mandatory = $true)][string]$FileName)
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
  $stem = $stem -replace '(_orig|_\d+)$', ''
  return $stem
}

$duplicateGroupsReport = New-Object System.Collections.Generic.List[object]
$assetMapRows = New-Object System.Collections.Generic.List[object]
$pdfRows = New-Object System.Collections.Generic.List[object]
$backupManifestRows = New-Object System.Collections.Generic.List[object]

# Group exact duplicates by hash.
$groups = $assetRows | Group-Object hash | Sort-Object Name

foreach ($g in $groups) {
  $items = @($g.Group)
  $copies = $items.Count
  $size = [int64]$items[0].bytes
  $category = $items[0].category
  $ext = $items[0].extension

  $referencedItems = @($items | Where-Object { $_.referenced })
  $ordered = @(
    $items | Sort-Object `
      @{ Expression = { if ($_.referenced) { 0 } else { 1 } } }, `
      @{ Expression = { if ($_.legacy_path -match '_orig(?=\.)') { 1 } else { 0 } } }, `
      @{ Expression = { $_.legacy_path.Length } }, `
      @{ Expression = { $_.legacy_path } }
  )
  $canonicalSource = $ordered[0]

  $mustKeepInLive = $false
  if ($category -eq "pdf" -or $category -eq "site-vendor") { $mustKeepInLive = $true }
  if ($referencedItems.Count -gt 0) { $mustKeepInLive = $true }

  $canonicalRel = $null
  $canonicalUrl = $null
  $canonicalAbs = $null

  if ($mustKeepInLive) {
    switch ($category) {
      "site-vendor" {
        $canonicalRel = "assets/vendor/weebly-site/" + $canonicalSource.legacy_path
      }
      "pdf" {
        $pdfDir = Join-Path $staticRoot "library\pdfs"
        $base = [System.IO.Path]::GetFileNameWithoutExtension($canonicalSource.legacy_path)
        $fileName = New-UniqueName -DirectoryPath $pdfDir -BaseName $base -Extension ".pdf"
        $canonicalRel = "library/pdfs/$fileName"
      }
      "audio" {
        $audioDir = Join-Path $staticRoot "media\audio"
        $base = [System.IO.Path]::GetFileNameWithoutExtension($canonicalSource.legacy_path)
        $fileName = New-UniqueName -DirectoryPath $audioDir -BaseName $base -Extension $ext
        $canonicalRel = "media/audio/$fileName"
      }
      "animation" {
        $animDir = Join-Path $staticRoot "media\animations"
        $base = [System.IO.Path]::GetFileNameWithoutExtension($canonicalSource.legacy_path)
        $fileName = New-UniqueName -DirectoryPath $animDir -BaseName $base -Extension $ext
        $canonicalRel = "media/animations/$fileName"
      }
      "image" {
        $imgDir = Join-Path $staticRoot "media\images"
        $base = [System.IO.Path]::GetFileNameWithoutExtension($canonicalSource.legacy_path)
        $fileName = New-UniqueName -DirectoryPath $imgDir -BaseName $base -Extension $ext
        $canonicalRel = "media/images/$fileName"
      }
      default {
        $miscDir = Join-Path $staticRoot "media\images"
        $base = [System.IO.Path]::GetFileNameWithoutExtension($canonicalSource.legacy_path)
        $fileName = New-UniqueName -DirectoryPath $miscDir -BaseName $base -Extension $ext
        $canonicalRel = "media/images/$fileName"
      }
    }

    $canonicalAbs = Join-Path $staticRoot ($canonicalRel -replace "/", "\")
    Copy-FilePreserveTimestamp -SourcePath $canonicalSource.source_path -DestinationPath $canonicalAbs
    $canonicalUrl = "/" + $canonicalRel
  }

  if ($copies -gt 1) {
    $duplicateGroupsReport.Add([pscustomobject]@{
      hash = $g.Name
      copies = $copies
      bytes_each = $size
      wasted_bytes = $size * ($copies - 1)
      category = $category
      canonical_legacy_path = $canonicalSource.legacy_path
      canonical_live_url = $canonicalUrl
      example_paths = ($items | Select-Object -First 5 -ExpandProperty legacy_path) -join "; "
    })
  }

  foreach ($item in $items) {
    $inLive = [bool]$mustKeepInLive
    $replacementType = "same"
    if (-not $mustKeepInLive) {
      $replacementType = "excluded-unreferenced"
    } elseif ($item.legacy_path -ne $canonicalSource.legacy_path) {
      $replacementType = "deduped"
    }

    $assetMapRows.Add([pscustomobject]@{
      legacy_path = $item.legacy_path
      canonical_path = if ($canonicalUrl) { $canonicalUrl } else { "" }
      hash = $item.hash
      bytes = $item.bytes
      kind = $item.category
      replacement_type = $replacementType
      poster_path = ""
      video_webm_path = ""
      video_mp4_path = ""
      backup_path = ""
      preserve_original_in_repo = if ($item.category -eq "pdf") { $true } else { $false }
      referenced = $item.referenced
      included_in_live_site = $inLive
    })

    if ($item.category -eq "pdf" -and $mustKeepInLive) {
      $pdfRows.Add([pscustomobject]@{
        legacy_path = $item.legacy_path
        canonical_path = $canonicalUrl
        hash = $item.hash
        title = [System.IO.Path]::GetFileNameWithoutExtension($item.legacy_path)
        referenced_by_pages = ""
        dedupe_group_id = $item.hash
      })
    }

    if (-not $mustKeepInLive -or $item.legacy_path -ne $canonicalSource.legacy_path) {
      if (-not $SkipBackup) {
        $reason = if (-not $mustKeepInLive) { "unreferenced" } else { "duplicate" }
        $backupSub = if ($reason -eq "duplicate") { "removed-duplicates" } else { "removed-unreferenced" }
        $backupDest = Join-Path (Join-Path $BackupRoot $backupSub) ($item.legacy_path -replace "/", "\")
        Copy-FilePreserveTimestamp -SourcePath $item.source_path -DestinationPath $backupDest
        $backupRel = Get-RelativePathUnix -Root $BackupRoot -Path $backupDest
        $backupManifestRows.Add([pscustomobject]@{
          legacy_path = $item.legacy_path
          backup_path = $backupRel
          hash = $item.hash
          reason = $reason
          canonical_live_path = $canonicalUrl
          bytes = $item.bytes
        })
      }
    }
  }
}

# Add alias mappings for Weebly "published/editor" paths that are referenced in HTML but not present as files.
$existingLegacyMap = @{}
foreach ($row in $assetMapRows) { $existingLegacyMap[[string]$row.legacy_path] = $true }

$includedRows = @($assetMapRows | Where-Object { [bool]$_.included_in_live_site -and -not [string]::IsNullOrWhiteSpace([string]$_.canonical_path) })
$uploadsAliasIndex = @{}
foreach ($r in $includedRows) {
  $lp = [string]$r.legacy_path
  if (-not $lp.StartsWith("uploads/")) { continue }
  $parts = $lp.Split("/")
  if ($parts.Count -lt 3) { continue }
  $bucket = ($parts[0..($parts.Count - 2)] -join "/")
  $leaf = $parts[-1]
  $ext = [System.IO.Path]::GetExtension($leaf).ToLowerInvariant()
  $norm = Get-NormalizedStem -FileName $leaf
  $key = "$bucket|$norm|$ext"
  if (-not $uploadsAliasIndex.ContainsKey($key)) {
    $uploadsAliasIndex[$key] = New-Object System.Collections.Generic.List[object]
  }
  $uploadsAliasIndex[$key].Add($r)
}

foreach ($refPath in $localRefSet) {
  $refNorm = $refPath.TrimStart("/")
  $refNoQuery = ($refNorm -split '[?#]', 2)[0]
  if ([string]::IsNullOrWhiteSpace($refNoQuery)) { continue }
  if ($existingLegacyMap.ContainsKey($refNoQuery)) { continue }
  if ($refNoQuery -notmatch '^uploads/.+/(published|editor)/([^/]+)$') { continue }

  $aliasFile = $Matches[2]
  $directGuess = $refNoQuery -replace '/(published|editor)/', '/'
  $target = $assetMapRows | Where-Object { $_.legacy_path -eq $directGuess -and [bool]$_.included_in_live_site } | Select-Object -First 1

  if (-not $target) {
    $parts = $refNoQuery.Split("/")
    $idx = [Array]::IndexOf($parts, "published")
    if ($idx -lt 0) { $idx = [Array]::IndexOf($parts, "editor") }
    if ($idx -gt 0) {
      $bucket = ($parts[0..($idx - 1)] -join "/")
      $ext = [System.IO.Path]::GetExtension($aliasFile).ToLowerInvariant()
      $norm = Get-NormalizedStem -FileName $aliasFile
      $key = "$bucket|$norm|$ext"
      if ($uploadsAliasIndex.ContainsKey($key)) {
        $target = $uploadsAliasIndex[$key] | Sort-Object @{Expression = { $_.bytes } }, @{Expression = { $_.legacy_path.Length } } | Select-Object -First 1
      }
    }
  }

  if ($target) {
    $assetMapRows.Add([pscustomobject]@{
      legacy_path = $refNoQuery
      canonical_path = [string]$target.canonical_path
      hash = [string]$target.hash
      bytes = [long]$target.bytes
      kind = [string]$target.kind
      replacement_type = "alias-published-editor"
      poster_path = ""
      video_webm_path = ""
      video_mp4_path = ""
      backup_path = ""
      preserve_original_in_repo = [bool]$target.preserve_original_in_repo
      referenced = $true
      included_in_live_site = $true
    })
    $existingLegacyMap[$refNoQuery] = $true
  }
}

# Emit mapping files.
$assetMapCsv = Join-Path $migrationRoot "legacy-asset-to-canonical-map.csv"
$assetMapRows | Sort-Object legacy_path | Export-Csv -LiteralPath $assetMapCsv -NoTypeInformation -Encoding UTF8

$dupeCsv = Join-Path $migrationRoot "exact-duplicate-groups.csv"
$duplicateGroupsReport | Sort-Object wasted_bytes -Descending | Export-Csv -LiteralPath $dupeCsv -NoTypeInformation -Encoding UTF8

$backupManifestCsv = Join-Path $migrationRoot "proton-backup-manifest.csv"
$backupManifestRows | Export-Csv -LiteralPath $backupManifestCsv -NoTypeInformation -Encoding UTF8

($assetMapRows | Sort-Object legacy_path | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $dataRoot "media-map.json") -Encoding utf8
Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "media-map.yaml") -Items ($assetMapRows | Sort-Object legacy_path) -KeyOrder @(
  "legacy_path","canonical_path","hash","kind","replacement_type","poster_path","video_webm_path","video_mp4_path","backup_path","preserve_original_in_repo","referenced","included_in_live_site","bytes"
)

($pdfRows | Sort-Object legacy_path | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $dataRoot "pdf-map.json") -Encoding utf8
Write-SimpleYamlListOfMaps -Path (Join-Path $dataRoot "pdf-map.yaml") -Items ($pdfRows | Sort-Object legacy_path) -KeyOrder @(
  "legacy_path","canonical_path","hash","title","referenced_by_pages","dedupe_group_id"
)

$summaryLines = @(
  "Source asset files: $($assetRows.Count)",
  "Unique hash groups: $($groups.Count)",
  "Duplicate hash groups: $($duplicateGroupsReport.Count)",
  "Potential exact duplicate savings: $(($duplicateGroupsReport | Measure-Object wasted_bytes -Sum).Sum)",
  "Live asset mappings: $($assetMapRows.Count)",
  "Live included assets: $(($assetMapRows | Where-Object included_in_live_site).Count)",
  "Excluded/unreferenced assets: $(($assetMapRows | Where-Object { -not $_.included_in_live_site }).Count)",
  "Backed up excluded/duplicate files: $($backupManifestRows.Count)",
  "Generated UTC: $([DateTime]::UtcNow.ToString('o'))"
)
Write-LinesUtf8NoBom -Path (Join-Path $migrationRoot "asset-dedupe-summary.txt") -Lines $summaryLines

Write-Output "Dedupe complete."
Write-Output "Asset map: $assetMapCsv"
Write-Output "Duplicate groups: $dupeCsv"
Write-Output "PDF map: $(Join-Path $dataRoot 'pdf-map.json')"
Write-Output "Backup manifest: $backupManifestCsv"
