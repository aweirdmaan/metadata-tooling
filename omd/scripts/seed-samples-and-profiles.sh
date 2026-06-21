#!/usr/bin/env bash
# Push sample rows + table profiles + column profiles into OMD,
# so the UI's "Sample Data" and "Profiler" tabs stop showing "No data".
#
# Required env: OMD_JWT
set -euo pipefail

BASE="http://localhost:8585/api/v1"
AUTH="Authorization: Bearer ${OMD_JWT:?OMD_JWT not set}"
CT="Content-Type: application/json"
CT_PATCH="Content-Type: application/json-patch+json"
TS_MS=$(($(date +%s) * 1000))

id_for() {
  curl -fsS -H "$AUTH" "$BASE/tables/name/$1" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])"
}

push() {
  local id=$1 endpoint=$2 body=$3 label=$4
  curl -fsS -X PUT -H "$AUTH" -H "$CT" "$BASE/tables/$id/$endpoint" -d "$body" >/dev/null && echo "  ~ $label"
}

OBS=$(id_for local-files.default.default.sensor_readings)
HL=$(id_for local-files.default.default.sensor_profiles)
AL=$(id_for local-files.default.default.zone_lookup)
HD=$(id_for local-files.default.default.sensor_profiles_enriched)

echo "Sample data..."
push "$OBS" sampleData '{
  "columns": ["sensor_id","metric_1","metric_2","ts"],
  "rows": [
    ["sensor_01728", 22.045, 31.118, "2024-01-11T15:00:00"],
    ["sensor_03608", 21.103, 38.096, "2024-01-09T04:00:00"],
    ["sensor_hv_001", 22.483, 41.117, "2024-01-01T16:00:00"],
    ["sensor_00598", 23.531, 50.020, "2024-10-17T14:00:00"],
    ["sensor_02772", 24.671, 35.128, "2024-07-05T06:00:00"],
    ["",             22.500, 40.100, "2024-06-15T12:00:00"],
    ["sensor_oor_021", 93.500, 28.012, "2024-08-22T09:00:00"]
  ]
}' "sensor_readings sampleData"

push "$HL" sampleData '{
  "columns": ["sensor_id","avg_metric_1","avg_metric_2","confidence"],
  "rows": [
    ["sensor_00001",  22.512, 41.104, 0.01],
    ["sensor_00002",  21.701, 35.130, 0.01],
    ["sensor_00003",  23.450, 27.021, 0.01],
    ["sensor_hv_001", 22.483, 41.117, 2.20],
    ["sensor_hv_002", 22.491, 50.110, 2.20],
    ["sensor_hv_003", 22.488, 32.115, 2.20],
    ["sensor_03608",  21.103, 38.097, 0.01]
  ]
}' "sensor_profiles sampleData"

push "$AL" sampleData '{
  "columns": ["bucket","zone_label"],
  "rows": [
    [20, "zone_a"],
    [21, "zone_b"],
    [22, "zone_c"],
    [23, "zone_d"],
    [24, "zone_e"]
  ]
}' "zone_lookup sampleData"

push "$HD" sampleData '{
  "columns": ["sensor_id","avg_metric_1","avg_metric_2","zone_label"],
  "rows": [
    ["sensor_00001",  22.512, 41.104, "zone_c"],
    ["sensor_00002",  21.701, 35.130, "zone_b"],
    ["sensor_00003",  23.450, 27.021, "zone_d"],
    ["sensor_hv_001", 22.483, 41.117, "zone_c"],
    ["sensor_oor_021", 93.500, 28.012, "unknown"]
  ]
}' "sensor_profiles_enriched sampleData"

echo "Table + column profiles..."
push "$OBS" tableProfile '{
  "tableProfile": {"timestamp": '"$TS_MS"', "columnCount": 4, "rowCount": 10246, "sizeInByte": 412300},
  "columnProfile": [
    {"timestamp": '"$TS_MS"', "name": "sensor_id", "valuesCount": 10246, "nullCount": 50, "nullProportion": 0.005, "uniqueCount": 9101, "uniqueProportion": 0.89, "missingCount": 50},
    {"timestamp": '"$TS_MS"', "name": "metric_1", "valuesCount": 10246, "nullCount": 0, "min": 20.0, "max": 99.9, "mean": 24.0, "median": 22.5},
    {"timestamp": '"$TS_MS"', "name": "metric_2", "valuesCount": 10246, "nullCount": 0, "min": 20.0, "max": 70.0, "mean": 45.0, "median": 45.0},
    {"timestamp": '"$TS_MS"', "name": "ts", "valuesCount": 10246, "nullCount": 0}
  ]
}' "sensor_readings tableProfile"

push "$HL" tableProfile '{
  "tableProfile": {"timestamp": '"$TS_MS"', "columnCount": 4, "rowCount": 9101, "sizeInByte": 178200},
  "columnProfile": [
    {"timestamp": '"$TS_MS"', "name": "sensor_id",    "valuesCount": 9101, "nullCount": 0, "uniqueCount": 9101, "uniqueProportion": 1.0},
    {"timestamp": '"$TS_MS"', "name": "avg_metric_1", "valuesCount": 9101, "nullCount": 0, "min": 20.0, "max": 99.9, "mean": 23.5},
    {"timestamp": '"$TS_MS"', "name": "avg_metric_2", "valuesCount": 9101, "nullCount": 0, "min": 20.0, "max": 70.0},
    {"timestamp": '"$TS_MS"', "name": "confidence",   "valuesCount": 9101, "nullCount": 0, "min": 0.01, "max": 2.20, "mean": 0.013}
  ]
}' "sensor_profiles tableProfile"

push "$AL" tableProfile '{
  "tableProfile": {"timestamp": '"$TS_MS"', "columnCount": 2, "rowCount": 5, "sizeInByte": 60},
  "columnProfile": [
    {"timestamp": '"$TS_MS"', "name": "bucket",     "valuesCount": 5, "nullCount": 0, "uniqueCount": 5, "min": 20, "max": 24},
    {"timestamp": '"$TS_MS"', "name": "zone_label", "valuesCount": 5, "nullCount": 0, "uniqueCount": 5}
  ]
}' "zone_lookup tableProfile"

push "$HD" tableProfile '{
  "tableProfile": {"timestamp": '"$TS_MS"', "columnCount": 4, "rowCount": 9101, "sizeInByte": 196500},
  "columnProfile": [
    {"timestamp": '"$TS_MS"', "name": "sensor_id",    "valuesCount": 9101, "nullCount": 0, "uniqueCount": 9101, "uniqueProportion": 1.0},
    {"timestamp": '"$TS_MS"', "name": "avg_metric_1", "valuesCount": 9101, "nullCount": 0, "min": 20.0, "max": 99.9},
    {"timestamp": '"$TS_MS"', "name": "avg_metric_2", "valuesCount": 9101, "nullCount": 0},
    {"timestamp": '"$TS_MS"', "name": "zone_label",   "valuesCount": 9101, "nullCount": 0, "uniqueCount": 6}
  ]
}' "sensor_profiles_enriched tableProfile"

echo "Database + schema + service descriptions..."
curl -fsS -X PATCH -H "$AUTH" -H "$CT_PATCH" "$BASE/databases/name/local-files.default" \
  -d '[{"op":"add","path":"/description","value":"Default logical database under the local-files service. Houses the parquet/CSV datasets produced by the Spark POC."}]' >/dev/null && echo "  ~ databases/local-files.default"
curl -fsS -X PATCH -H "$AUTH" -H "$CT_PATCH" "$BASE/databaseSchemas/name/local-files.default.default" \
  -d '[{"op":"add","path":"/description","value":"Default schema. Contains sensor_readings, sensor_profiles, zone_lookup, sensor_profiles_enriched."}]' >/dev/null && echo "  ~ databaseSchemas/local-files.default.default"
curl -fsS -X PATCH -H "$AUTH" -H "$CT_PATCH" "$BASE/services/databaseServices/name/local-files" \
  -d '[{"op":"add","path":"/description","value":"Custom database service representing parquet/CSV files on the local filesystem. Anchors lineage between physical files and the Pipeline entities that produced them."}]' >/dev/null && echo "  ~ services/databaseServices/local-files"

echo "Done."
