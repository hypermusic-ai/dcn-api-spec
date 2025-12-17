#requires -Version 7.0
<#
Generate protobuf schema from each service OpenAPI spec

- Finds:   services/*/openapi.yaml
- Runs:    npx @openapitools/openapi-generator-cli generate -g protobuf-schema
- Inputs:  the original openapi.yaml paths in the repo tree (so $ref paths work)
- Outputs: generated/proto/<service>/

Run from repo root:
  pwsh -File tools/generate-proto.ps1
#>

$ErrorActionPreference = "Stop"

# Repo root = one level above this script's directory (tools/ -> repo/)
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$GeneratedDir = Join-Path $RepoRoot "generated"
$ProtoDir     = Join-Path $GeneratedDir "proto"

# Clean only proto output (keep other generated artifacts if you want)
if (Test-Path $ProtoDir) {
  Remove-Item -Recurse -Force $ProtoDir
}
New-Item -ItemType Directory -Force -Path $ProtoDir | Out-Null

function Invoke-Npx {
  param([Parameter(Mandatory=$true)][string[]]$Args)

  Write-Host "`n> npx " -NoNewline -ForegroundColor DarkGray
  foreach ($a in $Args) { Write-Host "[$a]" -NoNewline -ForegroundColor DarkGray }
  Write-Host ""

  & npx @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: npx $($Args -join ' ')"
  }
}

# Find all services/*/openapi.yaml
$ServicesDir = Join-Path $RepoRoot "services"
if (-not (Test-Path $ServicesDir)) {
  throw "Missing services directory: $ServicesDir"
}

$ServiceSpecs = Get-ChildItem -Path $ServicesDir -Directory |
  ForEach-Object {
    $spec = Join-Path $_.FullName "openapi.yaml"
    if (Test-Path $spec) {
      [PSCustomObject]@{
        Name = $_.Name
        Spec = (Resolve-Path $spec).Path
      }
    }
  } | Where-Object { $_ -ne $null }

if (-not $ServiceSpecs -or $ServiceSpecs.Count -eq 0) {
  throw "No specs found at services/*/openapi.yaml"
}

Write-Host "RepoRoot: $RepoRoot" -ForegroundColor Cyan
Write-Host "Found OpenAPI specs:" -ForegroundColor Cyan
foreach ($svc in $ServiceSpecs) {
  Write-Host " - $($svc.Name): $($svc.Spec)"
}

# Generate protobuf for each service spec
Write-Host "`nGenerating protobuf schema (no bundling)..." -ForegroundColor Cyan
foreach ($svc in $ServiceSpecs) {
  $outProto = Join-Path $ProtoDir $svc.Name
  New-Item -ItemType Directory -Force -Path $outProto | Out-Null

  # derive package name from service dir name
  $pkg = ("dcn.{0}.v1" -f ($svc.Name -replace "-", "_"))

  Invoke-Npx @(
    "@openapitools/openapi-generator-cli@latest",
    "--",
    "generate",
    "-g", "protobuf-schema",
    "-i", $svc.Spec,
    "-o", $outProto,
    "--additional-properties", ("packageName={0}" -f $pkg)
  )

  Write-Host "Generated proto: $($svc.Name) -> $outProto (package=$pkg)" -ForegroundColor Green
}

Write-Host "`nDONE." -ForegroundColor Cyan
Write-Host "Proto output: $ProtoDir"
