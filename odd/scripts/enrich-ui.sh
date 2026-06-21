#!/usr/bin/env bash
# Populate ODD's UI surfaces that the bare ingestion API can't fill.
# Idempotent — re-runnable.
set -uo pipefail

BASE="http://localhost:8090"
CT="Content-Type: application/json"
note() { echo "  $1"; }

# Look up an entity's ID by its external_name
lookup_id() {
  local name=$1 sid
  sid=$(curl -fsS -X POST "$BASE/api/search" -H "$CT" -d "{\"query\":\"$name\",\"filters\":{}}" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['search_id'])")
  curl -fsS "$BASE/api/search/$sid/results?page=1&size=10" \
    | python3 -c "import sys,json
for e in json.load(sys.stdin)['items']:
    if e.get('external_name') == '$name' or e.get('internal_name') == '$name':
        print(e['id']); break"
}

OBS=$(lookup_id sensor_readings)
PROFS=$(lookup_id sensor_profiles)
ZONES=$(lookup_id zone_lookup)
ENR=$(lookup_id sensor_profiles_enriched)
echo "Entities: readings=$OBS profiles=$PROFS lookup=$ZONES enriched=$ENR"

# ---------------------------------------------------------------------------
echo "Creating + attaching owners..."
for o in "data-platform-team" "qa-team"; do
  curl -fsS -X POST "$BASE/api/owners" -H "$CT" -d "{\"name\":\"$o\"}" >/dev/null 2>&1 || true
  note "owner: $o"
done
for id in $OBS $PROFS $ZONES $ENR; do
  [[ -n "$id" ]] && curl -fsS -X POST "$BASE/api/dataentities/$id/ownership" -H "$CT" \
    -d '{"owner_name":"data-platform-team"}' >/dev/null 2>&1 \
    && note "attached data-platform-team to entity $id"
done

# ---------------------------------------------------------------------------
echo "Internal descriptions..."
put_desc() {
  curl -fsS -X PUT "$BASE/api/dataentities/$1/description" -H "$CT" \
    -d "{\"internal_description\":\"$2\"}" >/dev/null && note "description on $1"
}
[[ -n "$OBS"  ]] && put_desc "$OBS"  "Raw sensor readings ingested every minute. Source-of-truth for downstream aggregations."
[[ -n "$PROFS" ]] && put_desc "$PROFS" "Per-sensor profile aggregated from sensor_readings. Confidence = count(*)/100 (unclamped; high-volume sensors trip the downstream DQ check)."
[[ -n "$ZONES" ]] && put_desc "$ZONES" "Static reference. Buckets 20..24 only; out-of-range readings land as 'unknown' via the LEFT join."
[[ -n "$ENR"  ]] && put_desc "$ENR"  "Consumer-facing dataset: enriched sensor profile with zone label. Downstream dashboards subscribe here."

# ---------------------------------------------------------------------------
echo "Glossary terms..."
for spec in \
  'sensor-metric|A measured value from a physical sensor (temperature, pressure, humidity, etc).' \
  'zone|A geographical or logical bucket assignment derived from the sensor metric range.' \
  'tier1-asset|A consumer-facing dataset with active downstream readers; SLA-bound.'; do
  name="${spec%%|*}"
  defn="${spec##*|}"
  curl -fsS -X POST "$BASE/api/terms" -H "$CT" \
    -d "{\"name\":\"$name\",\"definition\":\"$defn\",\"namespace_name\":\"default\"}" >/dev/null 2>&1 \
    && note "term: $name"
done
attach_term() {
  curl -fsS -X POST "$BASE/api/dataentities/$1/terms" -H "$CT" \
    -d "{\"namespace_name\":\"default\",\"term_name\":\"$2\"}" >/dev/null 2>&1 \
    && note "term '$2' → entity $1"
}
[[ -n "$OBS"  ]] && attach_term "$OBS"  "sensor-metric"
[[ -n "$ZONES" ]] && attach_term "$ZONES" "zone"
[[ -n "$ENR"  ]] && attach_term "$ENR"  "tier1-asset"

# ---------------------------------------------------------------------------
DS_TOKEN=$(curl -fsS "$BASE/api/datasources?page=1&size=10" | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['token']['value'])")
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Pushing DASHBOARD (data consumer)..."
curl -sS -X POST "$BASE/ingestion/entities" -H "Authorization: Bearer $DS_TOKEN" -H "$CT" -d '{
  "data_source_oddrn": "//file/host/local",
  "items": [{
    "oddrn": "//bi/host/local/dashboards/sensor-overview",
    "name": "Sensor overview",
    "description": "Operations dashboard. Reads sensor_profiles_enriched.",
    "type": "DASHBOARD",
    "data_consumer": {"inputs": ["//file/host/local/pathpocs/odd/sample-data/zone_lookup.csv"]}
  }]
}' >/dev/null && note "dashboard pushed"

echo "Pushing JOB_RUN entities..."
curl -sS -X POST "$BASE/ingestion/entities" -H "Authorization: Bearer $DS_TOKEN" -H "$CT" -d "{
  \"data_source_oddrn\": \"//file/host/local\",
  \"items\": [
    {
      \"oddrn\": \"//spark/host/local/runs/build_sensor_profiles/$(date +%s)1\",
      \"name\": \"build_sensor_profiles run\",
      \"description\": \"Aggregation pass.\",
      \"type\": \"JOB_RUN\",
      \"data_transformer_run\": {\"transformer_oddrn\": \"//file/host/local/pathpocs/odd/sample-data/sensor_readings.csv\", \"start_time\": \"$NOW_ISO\", \"end_time\": \"$NOW_ISO\", \"status_reason\": \"Wrote 9101 profile rows.\", \"status\": \"SUCCESS\"}
    },
    {
      \"oddrn\": \"//spark/host/local/runs/enrich_with_zone_label/$(date +%s)2\",
      \"name\": \"enrich_with_zone_label run\",
      \"description\": \"Left join with zone_lookup.\",
      \"type\": \"JOB_RUN\",
      \"data_transformer_run\": {\"transformer_oddrn\": \"//file/host/local/pathpocs/odd/sample-data/zone_lookup.csv\", \"start_time\": \"$NOW_ISO\", \"end_time\": \"$NOW_ISO\", \"status_reason\": \"96 unknown labels.\", \"status\": \"SUCCESS\"}
    }
  ]
}" >/dev/null && note "job runs pushed"

echo ""
echo "Done. Refresh ODD UI."
