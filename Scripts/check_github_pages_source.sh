#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${GITHUB_REPOSITORY:-dannagrace/FreePrintStudio}"
PAGES_API_URL="${GITHUB_PAGES_API_URL:-https://api.github.com/repos/$REPOSITORY/pages}"

response_path="$(mktemp)"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! gh api "repos/$REPOSITORY/pages" >"$response_path" 2>/tmp/freeprintstudio-github-pages-source-gh.log; then
    printf 'BLOCKED: GitHub Pages settings could not be read with gh api for %s\n' "$REPOSITORY"
    sed 's/^/  /' /tmp/freeprintstudio-github-pages-source-gh.log
    rm -f "$response_path"
    exit 1
  fi
else
  headers=(
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )

  if [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer $GH_TOKEN")
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  status_code="$(curl -L -sS "${headers[@]}" -o "$response_path" -w '%{http_code}' "$PAGES_API_URL" || true)"

  if [[ "$status_code" != "200" ]]; then
    printf 'BLOCKED: GitHub Pages settings could not be read from %s (HTTP %s)\n' "$PAGES_API_URL" "$status_code"
    rm -f "$response_path"
    exit 1
  fi
fi

python3 - "$response_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)

build_type = str(payload.get("build_type", "")).strip()
html_url = str(payload.get("html_url", "")).strip()
source = payload.get("source") or {}
branch = str(source.get("branch", "")).strip()
source_path = str(source.get("path", "")).strip()

if build_type == "workflow":
    print(f"OK: GitHub Pages uses custom workflow publishing ({html_url})")
    raise SystemExit(0)

location = f"{branch}{source_path}" if branch or source_path else "unknown legacy source"
print(
    "BLOCKED: GitHub Pages build_type is "
    f"{build_type or 'missing'}, expected workflow; current source: {location}"
)
print("  Set Pages source to GitHub Actions, then run .github/workflows/pages.yml.")
raise SystemExit(1)
PY
python_status="$?"
rm -f "$response_path"
exit "$python_status"
