#!/usr/bin/env bash
# Open Data Discovery POC — one-shot setup.
#
# Brings up postgres + odd-platform, registers the local-files DataSource via
# the API (which returns a token), and pushes the four data entities + lineage.
#
# Re-runnable.

set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Prereqs

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require docker
require docker-compose
require curl
require python3

# ---------------------------------------------------------------------------
# Stack

echo "[1/4] Bringing up ODD Platform (postgres + odd-platform on :8090)..."
docker-compose up -d
echo "      waiting for platform health..."
until curl -sf http://localhost:8090/ >/dev/null 2>&1; do sleep 3; done
echo "      platform ready → http://localhost:8090  (no auth)"

# ---------------------------------------------------------------------------
# DataSource + token

echo "[2/4] Registering 'local-files' DataSource..."

# Idempotent: if it already exists, fetch its token
EXISTING=$(curl -fsS "http://localhost:8090/api/datasources" 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); m=[x for x in d.get('items',[]) if x.get('oddrn')=='//file/host/local']; print(m[0].get('token',{}).get('value','') if m else '')")

if [[ -z "$EXISTING" ]]; then
  RESP=$(curl -fsS -X POST http://localhost:8090/api/datasources \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Spark POC files",
      "oddrn": "//file/host/local",
      "description": "Parquet/CSV files produced by the Spark POC",
      "active": true,
      "connection_url": "file:///"
    }')
  ODD_TOKEN=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token']['value'])")
  echo "      created. token: ${ODD_TOKEN:0:8}..."
else
  ODD_TOKEN="$EXISTING"
  echo "      already exists. token: ${ODD_TOKEN:0:8}..."
fi
export ODD_TOKEN

# ---------------------------------------------------------------------------
# Seed + populate

echo "[3/4] Pushing entities, lineage, and JOB_RUN events..."
./scripts/seed-odd.sh
./scripts/populate-metadata.sh || true   # tolerates ODD's spec limits on JOB_RUN parents

# ---------------------------------------------------------------------------
# Done

cat <<EOF

[4/4] Done. Walk-through:

  - http://localhost:8090                             ODD Platform UI
  - left nav → Catalog                                4 entities under "Spark POC files"
  - click sensor_profiles_enriched → Lineage tab             two-hop graph

  To stop:           docker-compose down
  To wipe data:      docker-compose down -v && ./setup.sh
EOF
