# Stop on first error
$ErrorActionPreference = "Stop"

# Root paths
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ServicesDir = Join-Path $RepoRoot "services"
$DocsDir = Join-Path $RepoRoot "docs"

# Ensure output dir exists
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

Write-Host "Generating OpenAPI documentation with Redoc..." -ForegroundColor Cyan

$GeneratedServices = @()

Get-ChildItem -Path $ServicesDir -Directory | ForEach-Object {

    $serviceName = $_.Name
    $openapiFile = Join-Path $_.FullName "openapi.yaml"
    $outputFile = Join-Path $DocsDir "$serviceName.html"

    if (-Not (Test-Path $openapiFile)) {
        Write-Warning "Skipping $serviceName (no openapi.yaml)"
        return
    }

    Write-Host " → $serviceName" -ForegroundColor Green
    $script:GeneratedServices += $serviceName

    redoc-cli bundle `
        $openapiFile `
        --output $outputFile `
        --title "DCN - $serviceName API"
}

$indexItems = $GeneratedServices | ForEach-Object {
    $label = ($_ -replace "-service$", "") -replace "-", " "
    "        <li><a href=`"$_.html`">$label service</a></li>"
}

$indexHtml = @"
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>DCN API Specification</title>
    <style>
      :root {
        color-scheme: light dark;
        font-family:
          Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      body {
        margin: 0;
        min-height: 100vh;
        background: #f8fafc;
        color: #0f172a;
      }
      main {
        width: min(860px, calc(100vw - 40px));
        margin: 0 auto;
        padding: 64px 0;
      }
      h1 {
        margin: 0 0 12px;
        font-size: clamp(2rem, 5vw, 3rem);
        line-height: 1.05;
      }
      p {
        margin: 0 0 28px;
        max-width: 680px;
        color: #475569;
        font-size: 1rem;
        line-height: 1.6;
      }
      ul {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 12px;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      a {
        display: block;
        border: 1px solid #cbd5e1;
        border-radius: 8px;
        padding: 14px 16px;
        color: inherit;
        text-decoration: none;
        background: #ffffff;
      }
      a:hover {
        border-color: #64748b;
      }
      @media (prefers-color-scheme: dark) {
        body {
          background: #020617;
          color: #e2e8f0;
        }
        p {
          color: #94a3b8;
        }
        a {
          background: #0f172a;
          border-color: #334155;
        }
        a:hover {
          border-color: #94a3b8;
        }
      }
    </style>
  </head>
  <body>
    <main>
      <h1>DCN API Specification</h1>
      <p>OpenAPI reference documentation for the Decentralised Creative Network chain API services.</p>
      <ul>
$($indexItems -join "`n")
      </ul>
    </main>
  </body>
</html>
"@

Set-Content -Path (Join-Path $DocsDir "index.html") -Value $indexHtml -Encoding utf8
New-Item -ItemType File -Force -Path (Join-Path $DocsDir ".nojekyll") | Out-Null

Write-Host "✔ Documentation generated in /docs" -ForegroundColor Cyan
