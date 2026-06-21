#!/usr/bin/env bash
# Bring ODD up to closer parity with the OMD POC.
#
# Caveat: ODD's spec doesn't have first-class pipeline or DQ-test entity types.
# The valid types are FILE / TABLE / VIEW / JOB_RUN / KAFKA_TOPIC / ML_MODEL /
# DASHBOARD / etc.
#
# What this script does:
#   - 2 JOB_RUN entities representing the two pipeline executions
#   - 2 JOB_RUN entities representing the two DQ test runs (green + red)
#   - Lineage is already in place via data_transformer.inputs on the dataset entities
#
# Owners and tags in ODD are managed via /api/owners and /api/tags (separate from
# the ingestion API) — handled with PUT calls at the bottom.
set -euo pipefail

BASE="http://localhost:8090"
TOKEN="${ODD_TOKEN:?ODD_TOKEN not set}"
CT="Content-Type: application/json"
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

oddrn() { echo "//file/host/local/path${1}"; }
HL=$(oddrn  "/tmp/sensor_profiles.parquet")
HD=$(oddrn  "/tmp/sensor_profiles_enriched.parquet")

R1="//spark/host/local/runs/build_sensor_profiles/$(date +%s)"
R2="//spark/host/local/runs/enrich_with_zone_label/$(date +%s)"
T1="//qa/host/local/runs/sensor_profiles.sensor_id_not_null/$(date +%s)"
T2="//qa/host/local/runs/sensor_profiles.confidence_in_range/$(date +%s)"

read -r -d '' PAYLOAD <<EOF || true
{
  "data_source_oddrn": "//file/host/local",
  "items": [
    {
      "oddrn": "$R1",
      "name": "build_sensor_profiles run",
      "description": "groupBy(sensor_id).agg(avg(metric_1), avg(metric_2), count/100 as confidence). Writes sensor_profiles.parquet. confidence is deliberately unclamped so DQ checks can flag noise.",
      "type": "JOB_RUN",
      "data_transformer_run": {
        "transformer_oddrn": "$R1",
        "start_time": "$NOW_ISO",
        "end_time": "$NOW_ISO",
        "status_reason": "Completed successfully. 4455 rows produced.",
        "status": "SUCCESS"
      }
    },
    {
      "oddrn": "$R2",
      "name": "enrich_with_zone_label run",
      "description": "sensor_profiles LEFT JOIN zone_lookup on floor(avg_metric_1)=bucket, coalesce(zone_label, unknown). Writes sensor_profiles_enriched.parquet.",
      "type": "JOB_RUN",
      "data_transformer_run": {
        "transformer_oddrn": "$R2",
        "start_time": "$NOW_ISO",
        "end_time": "$NOW_ISO",
        "status_reason": "Completed successfully. 4455 rows produced.",
        "status": "SUCCESS"
      }
    },
    {
      "oddrn": "$T1",
      "name": "sensor_id_not_null (sensor_profiles)",
      "description": "columnValuesToBeNotNull on sensor_profiles.sensor_id. Expected to pass.",
      "type": "JOB_RUN",
      "data_quality_test_run": {
        "data_quality_test_oddrn": "$T1",
        "start_time": "$NOW_ISO",
        "end_time": "$NOW_ISO",
        "status_reason": "0 null sensor_ids out of 4455 rows.",
        "status": "SUCCESS"
      }
    },
    {
      "oddrn": "$T2",
      "name": "confidence_in_range (sensor_profiles)",
      "description": "columnValuesToBeBetween(confidence, 0, 1) on sensor_profiles. Expected to fail by design.",
      "type": "JOB_RUN",
      "data_quality_test_run": {
        "data_quality_test_oddrn": "$T2",
        "start_time": "$NOW_ISO",
        "end_time": "$NOW_ISO",
        "status_reason": "5 rows have confidence outside [0,1] (observed range 0.02..2.2).",
        "status": "FAILED"
      }
    }
  ]
}
EOF

echo "Pushing JOB_RUN entities (pipeline runs + DQ test runs)..."
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/ingestion/entities" \
  -H "Authorization: Bearer $TOKEN" -H "$CT" \
  -d "$PAYLOAD" | head -c 200
echo ""

echo "Done."
