#!/usr/bin/env bash
# Seed ODD's Data Quality surface.
#
# Two payloads (one per round-trip):
#   1. Two JOB-type entities defining the tests (data_quality_test block)
#   2. Two JOB_RUN entities recording one SUCCESS + one FAILED execution
#      (data_quality_test_run block referencing the test oddrn from step 1)
#
# Note: the public ODD contract jar 0.1.40 lists DataEntityType.UNKNOWN but
# the server actually accepts JOB — older contract, newer server. JOB is the
# type that registers an entity as a quality test (entity_class_ids includes 4).
#
# Idempotent — re-runs upsert.
set -uo pipefail

BASE="http://localhost:8090"
CT="Content-Type: application/json"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAMP=$(date +%s)

DS_TOKEN=$(curl -fsS "$BASE/api/datasources?page=1&size=10" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['token']['value'])")

echo "[1/2] Defining test entities (type=JOB)..."
curl -sS -X POST "$BASE/ingestion/entities" -H "Authorization: Bearer $DS_TOKEN" -H "$CT" -d '{
  "data_source_oddrn": "//file/host/local",
  "items": [
    {
      "oddrn": "//qa/host/local/tests/sensor_id_not_null",
      "name": "sensor_id_not_null",
      "description": "Asserts sensor_profiles.sensor_id is never null.",
      "type": "JOB",
      "data_quality_test": {
        "suite_name": "sensor_profiles_quality",
        "expectation": {"type": "NOT_NULL"},
        "dataset_list": ["//file/host/local/pathpocs/odd/sample-data/sensor_readings.csv"],
        "linked_url_list": []
      }
    },
    {
      "oddrn": "//qa/host/local/tests/confidence_in_range",
      "name": "confidence_in_range",
      "description": "Asserts confidence in [0,1]. Expected to fail by design (high-volume sensors land > 1).",
      "type": "JOB",
      "data_quality_test": {
        "suite_name": "sensor_profiles_quality",
        "expectation": {"type": "BETWEEN_0_AND_1"},
        "dataset_list": ["//file/host/local/pathpocs/odd/sample-data/sensor_readings.csv"],
        "linked_url_list": []
      }
    }
  ]
}' >/dev/null && echo "  ~ tests defined"

echo "[2/2] Recording test runs (one SUCCESS, one FAILED)..."
curl -sS -X POST "$BASE/ingestion/entities" -H "Authorization: Bearer $DS_TOKEN" -H "$CT" -d "{
  \"data_source_oddrn\": \"//file/host/local\",
  \"items\": [
    {
      \"oddrn\": \"//qa/host/local/tests/sensor_id_not_null/runs/$STAMP\",
      \"name\": \"sensor_id_not_null run\",
      \"type\": \"JOB_RUN\",
      \"data_quality_test_run\": {
        \"data_quality_test_oddrn\": \"//qa/host/local/tests/sensor_id_not_null\",
        \"start_time\": \"$NOW\",
        \"end_time\": \"$NOW\",
        \"status_reason\": \"0 null sensor_ids in 9101 rows.\",
        \"status\": \"SUCCESS\"
      }
    },
    {
      \"oddrn\": \"//qa/host/local/tests/confidence_in_range/runs/$STAMP\",
      \"name\": \"confidence_in_range run\",
      \"type\": \"JOB_RUN\",
      \"data_quality_test_run\": {
        \"data_quality_test_oddrn\": \"//qa/host/local/tests/confidence_in_range\",
        \"start_time\": \"$NOW\",
        \"end_time\": \"$NOW\",
        \"status_reason\": \"5 rows have confidence outside [0,1] (observed 0.01..2.20).\",
        \"status\": \"FAILED\"
      }
    }
  ]
}" >/dev/null && echo "  ~ runs recorded (SUCCESS + FAILED)"

echo "Done."
