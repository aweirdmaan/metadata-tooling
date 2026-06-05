#!/usr/bin/env bash
# Push DataEntities + lineage + DQ into ODD Platform via the Ingestion API.
# Required env: ODD_TOKEN (collector token from the ODD UI: Management → Collectors → +Add)
set -euo pipefail

BASE="http://localhost:8090"
TOKEN="${ODD_TOKEN:?ODD_TOKEN not set — create one in ODD UI → Management → Collectors}"
CT="Content-Type: application/json"

# ODD identifies each entity with an OddRN. For the POC, build them as
# //file/host/local/path... so they read sensibly in the UI.
oddrn_table() { echo "//file/host/local/path${1}"; }

OBS=$(oddrn_table  "pocs/odd/sample-data/sensor_readings.csv")
AL=$(oddrn_table   "pocs/odd/sample-data/zone_lookup.csv")
HL=$(oddrn_table   "/tmp/sensor_profiles.parquet")
HD=$(oddrn_table   "/tmp/sensor_profiles_enriched.parquet")
DS=$(oddrn_table   "")
NOW_MS=$(($(date +%s) * 1000))

# Build a single ingestion payload with all four data entities + two lineage edges.
read -r -d '' PAYLOAD <<EOF || true
{
  "data_source_oddrn": "//file/host/local",
  "items": [
    {
      "oddrn": "$OBS",
      "name": "sensor_readings",
      "description": "Raw sensor readings. Seeded with deliberate quality issues so DQ checks have something to catch.",
      "owner": "//file/host/local",
      "type": "FILE",
      "metadata": [{
        "schema_url": "https://raw.githubusercontent.com/opendatadiscovery/opendatadiscovery-specification/main/specification/extensions/file.json",
        "metadata": {"file_format": "csv", "rows": 10151}
      }],
      "dataset": {
        "field_list": [
          {"oddrn": "$OBS/columns/sensor_id", "name": "sensor_id", "type": {"type": "TYPE_STRING", "is_nullable": true}, "description": "Sensor identifier", "is_primary_key": false},
          {"oddrn": "$OBS/columns/metric_1",       "name": "metric_1",       "type": {"type": "TYPE_NUMBER", "is_nullable": false}, "description": "Primary metric reading"},
          {"oddrn": "$OBS/columns/metric_2",       "name": "metric_2",       "type": {"type": "TYPE_NUMBER", "is_nullable": false}, "description": "Secondary metric reading"},
          {"oddrn": "$OBS/columns/ts",        "name": "ts",        "type": {"type": "TYPE_DATETIME", "is_nullable": false}, "description": "Reading timestamp"}
        ]
      }
    },
    {
      "oddrn": "$AL",
      "name": "zone_lookup",
      "description": "Static reference: floor(metric_1) → zone_label. 92-94 intentionally absent so out-of-range readings land as unknown.",
      "type": "FILE",
      "dataset": {
        "field_list": [
          {"oddrn": "$AL/columns/bucket", "name": "bucket", "type": {"type": "TYPE_INTEGER", "is_nullable": false}},
          {"oddrn": "$AL/columns/zone_label", "name": "zone_label", "type": {"type": "TYPE_STRING",  "is_nullable": false}}
        ]
      }
    },
    {
      "oddrn": "$HL",
      "name": "sensor_profiles",
      "description": "Per-sensor profile derived by aggregating sensor_readings. confidence = count(*)/100 (unclamped on purpose).",
      "type": "FILE",
      "dataset": {
        "field_list": [
          {"oddrn": "$HL/columns/sensor_id",  "name": "sensor_id",  "type": {"type": "TYPE_STRING", "is_nullable": false}},
          {"oddrn": "$HL/columns/avg_metric_1",   "name": "avg_metric_1",   "type": {"type": "TYPE_NUMBER", "is_nullable": false}},
          {"oddrn": "$HL/columns/avg_metric_2",   "name": "avg_metric_2",   "type": {"type": "TYPE_NUMBER", "is_nullable": false}},
          {"oddrn": "$HL/columns/confidence", "name": "confidence", "type": {"type": "TYPE_NUMBER", "is_nullable": false}}
        ]
      },
      "data_transformer": {
        "inputs": ["$OBS"]
      }
    },
    {
      "oddrn": "$HD",
      "name": "sensor_profiles_enriched",
      "description": "sensor_profiles enriched by left-joining zone_lookup on floor(avg_metric_1); unmatched buckets land as 'unknown'.",
      "type": "FILE",
      "dataset": {
        "field_list": [
          {"oddrn": "$HD/columns/sensor_id",  "name": "sensor_id",  "type": {"type": "TYPE_STRING", "is_nullable": false}},
          {"oddrn": "$HD/columns/avg_metric_1",   "name": "avg_metric_1",   "type": {"type": "TYPE_NUMBER", "is_nullable": false}},
          {"oddrn": "$HD/columns/avg_metric_2",   "name": "avg_metric_2",   "type": {"type": "TYPE_NUMBER", "is_nullable": false}},
          {"oddrn": "$HD/columns/zone_label", "name": "zone_label", "type": {"type": "TYPE_STRING", "is_nullable": false}}
        ]
      },
      "data_transformer": {
        "inputs": ["$HL", "$AL"]
      }
    }
  ]
}
EOF

echo "Pushing entities to ODD Platform..."
curl -sS -w "\nHTTP %{http_code}\n" -X POST "$BASE/ingestion/entities" \
  -H "Authorization: Bearer $TOKEN" \
  -H "$CT" \
  -d "$PAYLOAD" | head -c 200
echo ""
echo "Done."
