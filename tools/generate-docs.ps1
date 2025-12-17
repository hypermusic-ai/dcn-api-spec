# Stop on first error
$ErrorActionPreference = "Stop"

# Root paths
$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ServicesDir = Join-Path $RepoRoot "services"
$DocsDir = Join-Path $RepoRoot "docs"

# Ensure output dir exists
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

Write-Host "Generating OpenAPI documentation with Redoc..." -ForegroundColor Cyan

Get-ChildItem -Path $ServicesDir -Directory | ForEach-Object {

    $serviceName = $_.Name
    $openapiFile = Join-Path $_.FullName "openapi.yaml"
    $outputFile = Join-Path $DocsDir "$serviceName.html"

    if (-Not (Test-Path $openapiFile)) {
        Write-Warning "Skipping $serviceName (no openapi.yaml)"
        return
    }

    Write-Host " → $serviceName" -ForegroundColor Green

    redoc-cli bundle `
        $openapiFile `
        --output $outputFile `
        --title "DCN - $serviceName API"
}

Write-Host "✔ Documentation generated in /docs" -ForegroundColor Cyan
