#!/usr/bin/env bash
# OpenMetadata POC — one-shot setup.
#
# Brings up the OMD stack, downloads the Spark Agent jar, prompts for the
# ingestion-bot JWT, runs the Spark jobs, registers entities + lineage + DQ,
# and populates governance metadata.
#
# Re-runnable. Existing containers are reused; seed scripts are idempotent.

set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Prereqs

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require docker
require docker-compose
require curl
require sbt
require python3

JAVA_HOME_EXPECTED="/opt/homebrew/opt/openjdk@21"
if [[ ! -d "$JAVA_HOME_EXPECTED" ]]; then
  echo "missing: JDK 21 at $JAVA_HOME_EXPECTED (brew install openjdk@21)" >&2
  exit 1
fi
export JAVA_HOME="$JAVA_HOME_EXPECTED"

# ---------------------------------------------------------------------------
# Stack

echo "[1/6] Bringing up OMD stack (postgres + elasticsearch + server + ingestion)..."
docker-compose up -d
echo "      waiting for server health..."
until [ "$(docker inspect -f '{{.State.Health.Status}}' openmetadata_server 2>/dev/null)" = "healthy" ]; do sleep 3; done
echo "      server healthy → http://localhost:8585  (admin@open-metadata.org / admin)"

# ---------------------------------------------------------------------------
# Spark Agent jar

echo "[2/6] Fetching OpenMetadata Spark Agent jar..."
mkdir -p lib
if [[ ! -s lib/openmetadata-spark-agent-1.1.jar ]]; then
  curl -fsSL -o lib/openmetadata-spark-agent-1.1.jar \
    https://github.com/open-metadata/openmetadata-spark-agent/releases/download/1.1/openmetadata-spark-agent-1.1.jar
  echo "      jar downloaded (~20MB)"
else
  echo "      jar already present"
fi

# ---------------------------------------------------------------------------
# JWT

if [[ -z "${OMD_JWT:-}" ]]; then
  cat <<EOF

[3/6] OMD_JWT not set in your environment.

      Get the ingestion-bot token from the OMD UI:
        1. open http://localhost:8585
        2. login: admin@open-metadata.org / admin
        3. Settings (gear, top-right) → Bots → ingestion-bot → Token
        4. click the eye icon, copy the long ey... string

      Then either re-run with the env var:
        OMD_JWT="ey..." ./setup.sh

      ...or paste the token here now (it won't be saved):
EOF
  read -rp "      OMD_JWT: " OMD_JWT
  export OMD_JWT
  echo
fi

# ---------------------------------------------------------------------------
# Spark jobs

echo "[4/6] Running Spark jobs (this also produces lineage events)..."
sbt -batch \
  "runMain com.poc.omd.BuildSensorProfiles --input-path sample-data/sensor_readings.csv --output-path /tmp/sensor_profiles.parquet" 2>&1 | grep -E "Emitting lineage|Exception|Total time" | tail -5
sbt -batch \
  "runMain com.poc.omd.EnrichWithZoneLabel --sensor-profiles-path /tmp/sensor_profiles.parquet --zone-lookup-path sample-data/zone_lookup.csv --output-path /tmp/sensor_profiles_enriched.parquet" 2>&1 | grep -E "Emitting lineage|Exception|Total time" | tail -5

# ---------------------------------------------------------------------------
# Seed entities + lineage + DQ + curation

echo "[5/6] Registering entities, lineage, DQ tests, and metadata via OMD API..."
./scripts/register-entities.sh
./scripts/seed-lineage.sh
./scripts/seed-dq.sh
./scripts/populate-metadata.sh
./scripts/seed-samples-and-profiles.sh

# ---------------------------------------------------------------------------
# Done

cat <<EOF

[6/6] Done. Walk-through:

  - http://localhost:8585                             OMD UI
  - search "sensor_profiles_enriched" → Lineage tab   two-hop lineage graph
  - open "sensor_profiles" → Data Quality tab         green + red mix
  - Lineage tab on sensor_profiles                    red DQ badge on the node
  - Insights (left nav)                               governance dashboard

  To bring everything down:  docker-compose down
  To wipe data + restart:    docker-compose down -v && ./setup.sh
EOF
