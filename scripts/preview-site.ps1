param(
    [string]$Root = (Join-Path $PSScriptRoot "..\docs"),
    [int[]]$CandidatePorts = @(8080, 8081, 8090, 5500, 5501),
    [switch]$AutoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MimeType {
    param([string]$Path)

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        ".html" { "text/html; charset=utf-8" }
        ".htm"  { "text/html; charset=utf-8" }
        ".css"  { "text/css; charset=utf-8" }
        ".js"   { "application/javascript; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".txt"  { "text/plain; charset=utf-8" }
        ".xml"  { "application/xml; charset=utf-8" }
        ".svg"  { "image/svg+xml" }
        ".png"  { "image/png" }
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".gif"  { "image/gif" }
        ".webp" { "image/webp" }
        ".ico"  { "image/x-icon" }
        ".mp4"  { "video/mp4" }
        ".webm" { "video/webm" }
        ".mp3"  { "audio/mpeg" }
        ".wav"  { "audio/wav" }
        ".ogg"  { "audio/ogg" }
        ".pdf"  { "application/pdf" }
        ".woff" { "font/woff" }
        ".woff2" { "font/woff2" }
        ".ttf"  { "font/ttf" }
        ".otf"  { "font/otf" }
        default { "application/octet-stream" }
    }
}

function Write-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Body,
        [string]$ContentType = "text/plain; charset=utf-8"
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

$rootFull = [IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Site root not found: $rootFull"
}

$projectBasePath = ""
$siteConfigPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\site-src\data\site.json"))
if (Test-Path -LiteralPath $siteConfigPath) {
    try {
        $siteConfig = Get-Content -LiteralPath $siteConfigPath -Raw | ConvertFrom-Json
        $bp = [string]$siteConfig.github_pages_project_base_path
        if (-not [string]::IsNullOrWhiteSpace($bp)) {
            $bp = $bp.Replace("\", "/").Trim()
            if (-not $bp.StartsWith("/")) { $bp = "/" + $bp }
            $bp = $bp.TrimEnd("/")
            if ($bp -ne "/") { $projectBasePath = $bp }
        }
    } catch {}
}

$listener = $null
$selectedPort = $null

foreach ($port in $CandidatePorts) {
    $candidate = New-Object System.Net.HttpListener
    $candidate.Prefixes.Add("http://127.0.0.1:$port/")
    $candidate.Prefixes.Add("http://localhost:$port/")
    try {
        $candidate.Start()
        $listener = $candidate
        $selectedPort = $port
        break
    }
    catch {
        try { $candidate.Close() } catch {}
    }
}

if (-not $listener) {
    throw "Unable to start preview server. Tried ports: $($CandidatePorts -join ', ')"
}

$url = "http://127.0.0.1:$selectedPort/"
$urlFile = Join-Path $env:TEMP "aliusresearch-preview-url.txt"
Set-Content -LiteralPath $urlFile -Value $url -Encoding UTF8

Write-Host "Alius Research preview server"
Write-Host "Root: $rootFull"
Write-Host "URL : $url"
Write-Host "Press Ctrl+C to stop."

if ($AutoOpen) {
    try { Start-Process $url | Out-Null } catch {}
}

try {
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
        }
        catch [System.Net.HttpListenerException] {
            break
        }

        $request = $context.Request
        $response = $context.Response
        $response.Headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        $response.Headers["Pragma"] = "no-cache"
        $response.Headers["Expires"] = "0"

        $requestPath = [Uri]::UnescapeDataString($request.Url.AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($requestPath)) {
            $requestPath = "/"
        }
        if (-not [string]::IsNullOrWhiteSpace($projectBasePath)) {
            if ($requestPath -eq $projectBasePath) {
                $requestPath = "/"
            }
            elseif ($requestPath.StartsWith($projectBasePath + "/")) {
                $requestPath = $requestPath.Substring($projectBasePath.Length)
                if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "/" }
            }
        }

        try {
            $relative = $requestPath.TrimStart("/").Replace("/", "\")
            $target = Join-Path $rootFull $relative

            if (Test-Path -LiteralPath $target -PathType Container) {
                $target = Join-Path $target "index.html"
            }
            elseif (-not (Test-Path -LiteralPath $target -PathType Leaf) -and -not [IO.Path]::GetExtension($target)) {
                $htmlTarget = "$target.html"
                if (Test-Path -LiteralPath $htmlTarget -PathType Leaf) {
                    $target = $htmlTarget
                }
            }

            $targetFull = [IO.Path]::GetFullPath($target)
            if (-not $targetFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Host ("403 {0}" -f $request.Url.AbsolutePath)
                Write-Response -Response $response -StatusCode 403 -Body "Forbidden"
                continue
            }

            if (-not (Test-Path -LiteralPath $targetFull -PathType Leaf)) {
                Write-Host ("404 {0}" -f $request.Url.AbsolutePath)
                Write-Response -Response $response -StatusCode 404 -Body "Not Found"
                continue
            }

            $response.StatusCode = 200
            $response.ContentType = Get-MimeType -Path $targetFull

            $fileInfo = Get-Item -LiteralPath $targetFull
            $response.ContentLength64 = $fileInfo.Length

            Write-Host ("200 {0}" -f $request.Url.AbsolutePath)

            if ($request.HttpMethod -ne "HEAD") {
                $stream = [IO.File]::OpenRead($targetFull)
                try {
                    $stream.CopyTo($response.OutputStream)
                }
                finally {
                    $stream.Dispose()
                }
            }

            $response.OutputStream.Close()
        }
        catch {
            try {
                if (-not $response.OutputStream.CanWrite) {
                    continue
                }
                Write-Host ("500 {0} :: {1}" -f $request.Url.AbsolutePath, $_.Exception.Message)
                Write-Response -Response $response -StatusCode 500 -Body "Internal Server Error"
            }
            catch {}
        }
    }
}
finally {
    if ($listener) {
        try { $listener.Stop() } catch {}
        try { $listener.Close() } catch {}
    }
}
