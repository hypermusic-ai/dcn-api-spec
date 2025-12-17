#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES_DIR="$REPO_ROOT/services"
OUT_DIR="$REPO_ROOT/docs"

# Ensure output dir exists
mkdir -p "$OUT_DIR"

# Ensure redoc-cli exists
if ! command -v redoc-cli >/dev/null 2>&1; then
  echo "ERROR: redoc-cli not found. Install it with: npm i -g redoc-cli" >&2
  exit 1
fi

echo "Generating OpenAPI documentation with Redoc..."
echo "Repo: $REPO_ROOT"
echo "Out:  $OUT_DIR"
echo

shopt -s nullglob
found_any=0

for svc_dir in "$SERVICES_DIR"/*/; do
  svc_name="$(basename "$svc_dir")"
  spec="$svc_dir/openapi.yaml"
  out="$OUT_DIR/${svc_name}.html"

  if [[ ! -f "$spec" ]]; then
    echo "Skipping $svc_name (no openapi.yaml)"
    continue
  fi

  found_any=1
  echo "→ $svc_name"

  # fail fast on invalid specs
  redoc-cli lint "$spec"

  redoc-cli bundle "$spec" \
    --output "$out" \
    --title "DCN – ${svc_name} API"
done

if [[ "$found_any" -eq 0 ]]; then
  echo "ERROR: No OpenAPI specs found under $SERVICES_DIR/*/openapi.yaml" >&2
  exit 2
fi

echo
echo "✔ Done. Generated docs in: $OUT_DIR"
