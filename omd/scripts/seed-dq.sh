#!/usr/bin/env bash
# Seed two DQ test cases on local-files.default.default.sensor_profiles
# and post one result each — one green (sensor_id not null) and one red
# (confidence in [0,1] with 5 high-volume sensors trip > 1).
#
# Required env: OMD_JWT
set -euo pipefail

BASE="http://localhost:8585/api/v1"
AUTH="Authorization: Bearer ${OMD_JWT:?OMD_JWT not set}"
CT="Content-Type: application/json"
TABLE_FQN="local-files.default.default.sensor_profiles"
TS_MS=$(($(date +%s) * 1000))

put_or_skip() {
  local endpoint=$1 body=$2 label=$3
  if curl -fsS -X PUT -H "$AUTH" -H "$CT" "$BASE/$endpoint" -d "$body" >/dev/null; then
    echo "  ~ $label"
  else
    curl -fsS -X POST -H "$AUTH" -H "$CT" "$BASE/$endpoint" -d "$body" >/dev/null && echo "  + $label"
  fi
}

echo "Creating test cases on sensor_profiles..."

put_or_skip "dataQuality/testCases" '{
  "name": "sensor_id_not_null",
  "entityLink": "<#E::table::'"$TABLE_FQN"'::columns::sensor_id>",
  "testDefinition": "columnValuesToBeNotNull",
  "parameterValues": []
}' "test case: sensor_id_not_null"

put_or_skip "dataQuality/testCases" '{
  "name": "confidence_in_range",
  "entityLink": "<#E::table::'"$TABLE_FQN"'::columns::confidence>",
  "testDefinition": "columnValuesToBeBetween",
  "parameterValues": [
    {"name": "minValue", "value": "0"},
    {"name": "maxValue", "value": "1"}
  ]
}' "test case: confidence_in_range"

echo "Posting test results..."

curl -fsS -X POST -H "$AUTH" -H "$CT" \
  "$BASE/dataQuality/testCases/testCaseResults/$TABLE_FQN.sensor_id.sensor_id_not_null" \
  -d '{
    "timestamp": '"$TS_MS"',
    "testCaseStatus": "Success",
    "result": "0 null sensor_ids out of 9909 rows",
    "testResultValue": [{"name": "nullCount", "value": "0"}]
  }' >/dev/null && echo "  + result: sensor_id_not_null = Success"

curl -fsS -X POST -H "$AUTH" -H "$CT" \
  "$BASE/dataQuality/testCases/testCaseResults/$TABLE_FQN.confidence.confidence_in_range" \
  -d '{
    "timestamp": '"$TS_MS"',
    "testCaseStatus": "Failed",
    "result": "5 rows have confidence outside [0,1] (range observed: 0.01..2.2)",
    "testResultValue": [
      {"name": "minValue", "value": "0.01"},
      {"name": "maxValue", "value": "2.2"}
    ]
  }' >/dev/null && echo "  + result: confidence_in_range = Failed"

echo "Done."
