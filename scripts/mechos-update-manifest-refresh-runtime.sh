#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_PREFIX="${1:-}"
HELPER="$ROOT_PREFIX/usr/local/bin/mechos-update-helper"

log(){ printf '[MechOS Update Manifest Refresh] %s\n' "$*"; }
fail(){ printf '[MechOS Update Manifest Refresh] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$HELPER" ] || { log "update helper not present; skipping"; exit 0; }

python3 - "$HELPER" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
t=p.read_text(encoding='utf-8')
marker='# MECHOS_MANIFEST_REFRESH_V1'
if marker in t:
    raise SystemExit(0)

needle='''fetch_manifest(){\n  local tmp\n  tmp="$(mktemp "$CACHE_DIR/manifest.XXXXXX")"\n  if command -v curl >/dev/null 2>&1 && \\\n     curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \\\n       --connect-timeout 8 --max-time 20 "$MANIFEST_URL" -o "$tmp"; then\n'''
replacement='''fetch_manifest(){\n  # MECHOS_MANIFEST_REFRESH_V1\n  # raw.githubusercontent.com may briefly serve a cached branch file after a\n  # release is published. Every manual/automatic check uses a unique URL and\n  # explicit no-cache headers so Update Center sees the newest stable manifest.\n  local tmp fetch_url refresh\n  tmp="$(mktemp "$CACHE_DIR/manifest.XXXXXX")"\n  refresh="$(date +%s%N 2>/dev/null || date +%s)"\n  case "$MANIFEST_URL" in\n    *\\?*) fetch_url="${MANIFEST_URL}&_mechos_refresh=${refresh}" ;;\n    *)     fetch_url="${MANIFEST_URL}?_mechos_refresh=${refresh}" ;;\n  esac\n  if command -v curl >/dev/null 2>&1 && \\\n     curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \\\n       --header 'Cache-Control: no-cache' --header 'Pragma: no-cache' \\\n       --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 25 \\\n       "$fetch_url" -o "$tmp"; then\n'''
if needle not in t:
    raise SystemExit('[MechOS Update Manifest Refresh] fetch_manifest curl anchor missing')
t=t.replace(needle,replacement,1)
p.write_text(t,encoding='utf-8')
PY

chmod 0755 "$HELPER"
bash -n "$HELPER" || fail "update helper syntax failed after manifest refresh patch"
grep -Fq 'MECHOS_MANIFEST_REFRESH_V1' "$HELPER" || fail "manifest refresh marker missing"
grep -Fq '_mechos_refresh=' "$HELPER" || fail "cache-busting query missing"
grep -Fq 'Cache-Control: no-cache' "$HELPER" || fail "no-cache request header missing"

log "Update Center remote manifest checks now bypass stale GitHub/raw caches"
