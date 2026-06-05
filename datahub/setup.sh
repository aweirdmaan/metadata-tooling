#!/usr/bin/env bash
# DataHub POC — one-shot setup.
#
# Uses the `datahub` CLI's quickstart to bring up GMS + frontend + Kafka +
# OpenSearch + MySQL. Generates the token signing keys, runs the Spark jobs,
# seeds datasets + lineage + assertions, and populates pipelines + governance.
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
require sbt
require python3
require pip3
require openssl

JAVA_HOME_EXPECTED="/opt/homebrew/opt/openjdk@21"
if [[ ! -d "$JAVA_HOME_EXPECTED" ]]; then
  echo "missing: JDK 21 at $JAVA_HOME_EXPECTED (brew install openjdk@21)" >&2
  exit 1
fi
export JAVA_HOME="$JAVA_HOME_EXPECTED"

# Install datahub CLI if missing
if ! command -v datahub >/dev/null 2>&1; then
  if [[ -x "$HOME/Library/Python/3.9/bin/datahub" ]]; then
    export PATH="$HOME/Library/Python/3.9/bin:$PATH"
  else
    echo "Installing datahub CLI (acryl-datahub)..."
    pip3 install --user acryl-datahub
    export PATH="$HOME/Library/Python/3.9/bin:$PATH"
  fi
fi

# DataHub's Python docker client needs DOCKER_HOST when using colima
if [[ -S "$HOME/.colima/default/docker.sock" && -z "${DOCKER_HOST:-}" ]]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
fi

# ---------------------------------------------------------------------------
# Token signing keys (quickstart leaves these blank by default)

QS_ENV="$HOME/.datahub/quickstart/.env"
mkdir -p "$(dirname "$QS_ENV")"
if [[ ! -s "$QS_ENV" || ! "$(cat "$QS_ENV")" =~ DATAHUB_TOKEN_SERVICE_SIGNING_KEY ]]; then
  cat > "$QS_ENV" <<EOF
DATAHUB_TOKEN_SERVICE_SIGNING_KEY=$(openssl rand -hex 16)
DATAHUB_TOKEN_SERVICE_SALT=$(openssl rand -hex 8)
DATAHUB_VERSION=v1.5.0.6
UI_INGESTION_DEFAULT_CLI_VERSION=v1.5.0.6
EOF
  echo "[1/5] Wrote token signing keys to $QS_ENV"
else
  echo "[1/5] Token signing keys already set"
fi

# ---------------------------------------------------------------------------
# Stack

echo "[2/5] Bringing up DataHub quickstart (GMS + frontend + Kafka + OpenSearch + MySQL)..."
datahub docker quickstart >/dev/null 2>&1 || {
  # Fall back to compose directly if the CLI gets unhappy
  docker-compose --profile quickstart -p datahub \
    -f "$HOME/.datahub/quickstart/docker-compose.yml" \
    --env-file "$QS_ENV" up -d
}
echo "      waiting for GMS health..."
until curl -sf http://localhost:8080/health >/dev/null 2>&1; do sleep 3; done
until curl -sf http://localhost:9002/ >/dev/null 2>&1; do sleep 3; done
echo "      stack healthy:"
echo "        UI:  http://localhost:9002  (datahub / datahub)"
echo "        GMS: http://localhost:8080"

# ---------------------------------------------------------------------------
# Spark jobs

echo "[3/5] Running Spark jobs (lineage events go to GMS via the Acryl listener)..."
sbt -batch \
  "runMain com.poc.datahub.BuildSensorProfiles --input-path sample-data/sensor_readings.csv --output-path /tmp/sensor_profiles.parquet" 2>&1 | grep -E "Emitting|Total time" | tail -3 || true
sbt -batch \
  "runMain com.poc.datahub.EnrichWithZoneLabel --sensor-profiles-path /tmp/sensor_profiles.parquet --zone-lookup-path sample-data/zone_lookup.csv --output-path /tmp/sensor_profiles_enriched.parquet" 2>&1 | grep -E "Emitting|Total time" | tail -3 || true

# ---------------------------------------------------------------------------
# Seed + populate

echo "[4/5] Seeding datasets, lineage, assertions, dataJobs, owners, tiers, profiles..."
./scripts/seed-datahub.sh
./scripts/populate-metadata.sh

# ---------------------------------------------------------------------------
# Done

cat <<EOF

[5/5] Done. Walk-through:

  - http://localhost:9002                             DataHub UI
  - search "sensor_profiles_enriched" → Lineage              two-hop graph
  - open "sensor_profiles" → Validation tab            green + red assertions
  - left nav → Domains → "spark-poc"                  scoped asset list

  To stop:                  datahub docker quickstart --stop
  To wipe and restart:      datahub docker nuke && ./setup.sh
EOF
