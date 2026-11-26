# Local web server for this folder (program).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File start-local.ps1 [-Port 8791]
# Opens the browser automatically. Close this window to stop the server.
# If the preferred port is busy, tries the next free ports.
param([int]$Port = 8791)

$root = $PSScriptRoot
$listener = $null
$boundPort = $null
$maxTries = 20

for ($i = 0; $i -lt $maxTries; $i++) {
  $tryPort = $Port + $i
  $candidate = New-Object System.Net.HttpListener
  $candidate.Prefixes.Add("http://localhost:$tryPort/")
  try {
    $candidate.Start()
    $listener = $candidate
    $boundPort = $tryPort
    break
  } catch {
    try { $candidate.Close() } catch {}
  }
}

if (-not $listener) {
  Write-Output "Could not find a free port starting from $Port."
  Write-Output "Close other local servers and try again."
  exit 1
}

if ($boundPort -ne $Port) {
  Write-Output "Port $Port is busy. Using free port $boundPort instead."
}

Write-Output "Serving $root at http://localhost:$boundPort/"
Write-Output "Close this window to stop."
Start-Process "http://localhost:$boundPort/"

$mime = @{
  ".html"="text/html; charset=utf-8"; ".css"="text/css; charset=utf-8"; ".js"="text/javascript; charset=utf-8"
  ".json"="application/json"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg"; ".gif"="image/gif"
  ".webp"="image/webp"; ".svg"="image/svg+xml"; ".mp4"="video/mp4"; ".mp3"="audio/mpeg"; ".wav"="audio/wav"
  ".woff"="font/woff"; ".woff2"="font/woff2"; ".ico"="image/x-icon"
}

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $rawPath = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($rawPath -eq "/") { $rawPath = "/index.html" }
    $file = Join-Path $root ($rawPath -replace "/", "\")
    $resolved = [IO.Path]::GetFullPath($file)
    if ($resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved -PathType Leaf)) {
      $bytes = [IO.File]::ReadAllBytes($resolved)
      $ext = [IO.Path]::GetExtension($resolved).ToLower()
      $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
      $ctx.Response.ContentLength64 = $bytes.Length
      if ($ext -eq ".css" -or $ext -eq ".js" -or $ext -eq ".html") {
        $ctx.Response.Headers["Cache-Control"] = "no-cache"
      }
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
    }
    $ctx.Response.Close()
  } catch {
    # keep serving even if one request fails
  }
}
