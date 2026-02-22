Set-StrictMode -Version Latest

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-Utf8NoBomEncoding {
  return [System.Text.UTF8Encoding]::new($false)
}

function Write-TextFileUtf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
  )
  $parent = Split-Path -Parent $Path
  if ($parent) { Ensure-Directory -Path $parent }
  [System.IO.File]::WriteAllText($Path, $Content, (Get-Utf8NoBomEncoding))
}

function Write-LinesUtf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Lines
  )
  $parent = Split-Path -Parent $Path
  if ($parent) { Ensure-Directory -Path $parent }
  [System.IO.File]::WriteAllLines($Path, $Lines, (Get-Utf8NoBomEncoding))
}

function ConvertTo-Slug {
  param([Parameter(Mandatory = $true)][string]$Text)

  $t = $Text.ToLowerInvariant()
  $t = $t -replace '&[a-z0-9#]+;', '-'
  $t = $t -replace '[^a-z0-9]+', '-'
  $t = $t.Trim('-')
  if ([string]::IsNullOrWhiteSpace($t)) { return "page" }
  return $t
}

function Get-LongPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith("\\?\")) { return $full }
  if ($full.StartsWith("\\")) { return "\\?\UNC\" + $full.TrimStart("\") }
  return "\\?\" + $full
}

function Get-FileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead((Get-LongPath -Path $Path))
    try {
      return ([System.BitConverter]::ToString($sha.ComputeHash($fs))).Replace("-", "")
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
}

function Get-RelativePathUnix {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $rootFull = [System.IO.Path]::GetFullPath($Root)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  if (-not $rootFull.EndsWith("\")) { $rootFull += "\" }
  $rootUri = [uri]$rootFull
  $pathUri = [uri]$pathFull
  $relUri = $rootUri.MakeRelativeUri($pathUri)
  $rel = [uri]::UnescapeDataString($relUri.ToString())
  return $rel.Replace("\", "/")
}

function Copy-FilePreserveTimestamp {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )
  Ensure-Directory -Path (Split-Path -Parent $DestinationPath)
  $srcLong = Get-LongPath -Path $SourcePath
  $dstLong = Get-LongPath -Path $DestinationPath
  $inStream = [System.IO.File]::OpenRead($srcLong)
  try {
    $outStream = [System.IO.File]::Open($dstLong, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
      $inStream.CopyTo($outStream)
    } finally {
      $outStream.Dispose()
    }
  } finally {
    $inStream.Dispose()
  }
  try {
    [System.IO.File]::SetLastWriteTimeUtc($dstLong, [System.IO.File]::GetLastWriteTimeUtc($srcLong))
  } catch {}
}

function Read-TextFileSafe {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText((Get-LongPath -Path $Path))
}

function Try-GetRegexMatchValue {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [int]$Group = 1
  )
  $m = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($m.Success) { return $m.Groups[$Group].Value }
  return $null
}

function Get-HtmlDocumentParts {
  param([Parameter(Mandatory = $true)][string]$Html)

  $result = [ordered]@{
    HtmlTagAttributes = ""
    HeadInner = ""
    BodyTagAttributes = ""
    BodyInner = ""
    Title = ""
    MetaDescription = ""
  }

  $htmlAttrs = Try-GetRegexMatchValue -Text $Html -Pattern '<html\b([^>]*)>'
  if ($null -ne $htmlAttrs) { $result.HtmlTagAttributes = $htmlAttrs.Trim() }

  $headInner = Try-GetRegexMatchValue -Text $Html -Pattern '<head\b[^>]*>(.*?)</head>'
  if ($null -ne $headInner) { $result.HeadInner = $headInner }

  $bodyAttrs = Try-GetRegexMatchValue -Text $Html -Pattern '<body\b([^>]*)>'
  if ($null -ne $bodyAttrs) { $result.BodyTagAttributes = $bodyAttrs.Trim() }

  $bodyInner = Try-GetRegexMatchValue -Text $Html -Pattern '<body\b[^>]*>(.*?)</body>'
  if ($null -ne $bodyInner) { $result.BodyInner = $bodyInner }

  $title = Try-GetRegexMatchValue -Text $Html -Pattern '<title>(.*?)</title>'
  if ($null -ne $title) { $result.Title = ($title -replace '\s+', ' ').Trim() }

  $metaDesc = Try-GetRegexMatchValue -Text $Html -Pattern '<meta\s+name=["'']description["'']\s+content=["''](.*?)["'']'
  if ($null -ne $metaDesc) { $result.MetaDescription = $metaDesc }

  return [pscustomobject]$result
}

function Get-LocalUrlCandidatesFromText {
  param([Parameter(Mandatory = $true)][string]$Text)

  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  $pattern = '(?is)(?:href|src)\s*=\s*["'']([^"'']+)["'']|url\(([^)]+)\)'
  foreach ($m in [regex]::Matches($Text, $pattern)) {
    $raw = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $raw = $raw.Trim()
    $raw = $raw.Trim("'").Trim('"')
    $raw = $raw.Replace("\", "/")
    if ($raw -match '^(?:https?:|//|data:|mailto:|tel:|javascript:|#)') { continue }
    $pathPart = ($raw -split '[?#]', 2)[0]
    if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
    if ($pathPart.StartsWith("/")) { $pathPart = $pathPart.Substring(1) }
    if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
    [void]$set.Add($pathPart)
    try {
      [void]$set.Add([uri]::UnescapeDataString($pathPart))
    } catch {}
  }
  return $set
}

function Get-AssetCategory {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string]$Extension,
    [Parameter(Mandatory = $true)][long]$Bytes
  )

  if ($RelativePath.StartsWith("files/") -or $RelativePath.StartsWith("apps/")) {
    return "site-vendor"
  }

  switch ($Extension.ToLowerInvariant()) {
    ".pdf" { return "pdf" }
    ".mp3" { return "audio" }
    ".wav" { return "audio" }
    ".ogg" { return "audio" }
    ".m4a" { return "audio" }
    ".gif" {
      if ($Bytes -ge 2MB) { return "animation" }
      return "image"
    }
    ".png" { return "image" }
    ".jpg" { return "image" }
    ".jpeg" { return "image" }
    ".webp" { return "image" }
    default {
      return "other"
    }
  }
}

function Get-CanonicalPageRoute {
  param([Parameter(Mandatory = $true)][string]$LegacyHtmlFilename)

  $name = [System.IO.Path]::GetFileNameWithoutExtension($LegacyHtmlFilename).ToLowerInvariant()

  if ($name -eq "index") { return "/" }
  if ($name -match '^about$') { return "/about/" }
  if ($name -match '^team($|-)') { return "/about/team/$name/" }
  if ($name -match '^research($|1$)') { return "/research/" }
  if ($name -match '^projects$') { return "/research/projects/" }
  if ($name -match '^commentaries') { return "/research/commentaries/$name/" }
  if ($name -match '^bulletin0?([1-9]|10)($|-)') {
    if ($name -match '^bulletin(\d+)$') {
      return "/bulletin/issues/bulletin-$($Matches[1])/"
    }
    return "/bulletin/interviews/$name/"
  }
  if ($name -eq "bulletin") { return "/bulletin/" }
  if ($name -match '^workshop-') { return "/events/workshops/$name/" }
  if ($name -match '^journal-club|^journalclub|^symposium$|^events$|^attendees$|^travel-information$|^application-late$|^bicycle-day-workshop$') {
    return "/events/$name/"
  }
  if ($name -match '^podcast$|^episodes$|^track|^music$|^media$|^pics$|^images-visionnaires$') {
    return "/media/$name/"
  }
  if ($name -match 'podcast') { return "/media/podcast/$name/" }
  if ($name -match '^membership-renewal|^become-a-member$|^members1$|^researcher-members$|^newsletter$') {
    return "/community/$name/"
  }
  if ($name -match 'interview') { return "/articles/interviews/$name/" }
  if ($name -match 'psychedelic|dmt|consciousness|self|sleep|depersonal|peripersonal|qualius|physio|torus|anima|viscereality') {
    return "/research/projects/$name/"
  }
  if ($name -match '^(1|2|7|8)$|^teamtest|^oldcode$') {
    return "/archive/misc/$name/"
  }
  return "/pages/$name/"
}

function ConvertTo-YamlScalar {
  param([Parameter(Mandatory = $true)]$Value)
  if ($null -eq $Value) { return "null" }
  if ($Value -is [bool]) { return ($(if ($Value) { "true" } else { "false" })) }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return [string]$Value }
  $s = [string]$Value
  $s = $s.Replace("`r", "").Replace("`n", "\n")
  $s = $s.Replace("\", "\\").Replace('"', '\"')
  return '"' + $s + '"'
}

function Write-SimpleYamlListOfMaps {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Items,
    [string[]]$KeyOrder
  )

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($item in $Items) {
    $props = @()
    if ($KeyOrder -and $KeyOrder.Count -gt 0) {
      foreach ($k in $KeyOrder) {
        if ($item.PSObject.Properties.Name -contains $k) { $props += $k }
      }
      foreach ($p in $item.PSObject.Properties.Name) {
        if ($props -notcontains $p) { $props += $p }
      }
    } else {
      $props = @($item.PSObject.Properties.Name)
    }
    $first = $true
    foreach ($p in $props) {
      $v = $item.$p
      if ($first) {
        $lines.Add("- ${p}: $(ConvertTo-YamlScalar -Value $v)")
        $first = $false
      } else {
        $lines.Add("  ${p}: $(ConvertTo-YamlScalar -Value $v)")
      }
    }
  }
  Write-LinesUtf8NoBom -Path $Path -Lines ($lines.ToArray())
}

function Get-HashGroupedItems {
  param([Parameter(Mandatory = $true)][object[]]$Items)
  return $Items | Group-Object Hash
}

function New-RedirectHtml {
  param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$LegacyPath
  )
@"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=$TargetPath">
  <link rel="canonical" href="$TargetPath">
  <meta name="robots" content="noindex">
  <title>Redirecting...</title>
  <script>location.replace("$TargetPath");</script>
</head>
<body>
  <p>Redirecting from <code>$LegacyPath</code> to <a href="$TargetPath">$TargetPath</a>.</p>
</body>
</html>
"@
}
