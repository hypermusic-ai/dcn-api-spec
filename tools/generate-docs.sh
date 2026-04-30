#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES_DIR="$REPO_ROOT/services"
OUT_DIR="$REPO_ROOT/docs"

# Ensure output dir exists
mkdir -p "$OUT_DIR"

# Ensure Redocly CLI exists
REDOCLY_BIN="${REPO_ROOT}/node_modules/.bin/redocly"
if [[ ! -x "$REDOCLY_BIN" ]]; then
  if command -v redocly >/dev/null 2>&1; then
    REDOCLY_BIN="redocly"
  else
    echo "ERROR: redocly not found. Run npm ci or install it with: npm i -D @redocly/cli" >&2
    exit 1
  fi
fi

if [[ "${REDOCLY_BIN}" == "${REPO_ROOT}/node_modules/.bin/redocly" && ! -x "$REDOCLY_BIN" ]]; then
  echo "ERROR: local redocly binary is not executable: $REDOCLY_BIN" >&2
  exit 1
fi

echo "Generating OpenAPI documentation with Redoc..."
echo "Repo: $REPO_ROOT"
echo "Out:  $OUT_DIR"
echo

shopt -s nullglob
found_any=0
services=()

for svc_dir in "$SERVICES_DIR"/*/; do
  svc_name="$(basename "$svc_dir")"
  spec="$svc_dir/openapi.yaml"
  out="$OUT_DIR/${svc_name}.html"

  if [[ ! -f "$spec" ]]; then
    echo "Skipping $svc_name (no openapi.yaml)"
    continue
  fi

  found_any=1
  services+=("$svc_name")
  echo "→ $svc_name"

  # fail fast on invalid specs
  "$REDOCLY_BIN" lint "$spec"

  "$REDOCLY_BIN" build-docs "$spec" \
    --output="$out" \
    --title "DCN – ${svc_name} API"
done

if [[ "$found_any" -eq 0 ]]; then
  echo "ERROR: No OpenAPI specs found under $SERVICES_DIR/*/openapi.yaml" >&2
  exit 2
fi

index="$OUT_DIR/index.html"
{
  cat <<'HTML'
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
HTML

  for svc in "${services[@]}"; do
    label="${svc%-service}"
    label="${label//-/ }"
    printf '        <li><a href="%s.html">%s service</a></li>\n' "$svc" "$label"
  done

  cat <<'HTML'
      </ul>
    </main>
  </body>
</html>
HTML
} > "$index"

# Avoid Jekyll processing if this artifact is ever served by a Pages mode that
# enables it. Actions-based Pages serves the artifact directly, but this is cheap.
: > "$OUT_DIR/.nojekyll"

echo
echo "✔ Done. Generated docs in: $OUT_DIR"
