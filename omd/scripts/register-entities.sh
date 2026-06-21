#!/usr/bin/env bash
# Pre-register a Custom Database Service + the four POC tables in OMD,
# so the Spark Agent's lineage events have entities to attach to.
#
# Required env: OMD_JWT (ingestion-bot token from the OMD UI)
set -euo pipefail

BASE="http://localhost:8585/api/v1"
AUTH="Authorization: Bearer ${OMD_JWT:?OMD_JWT not set}"
CT="Content-Type: application/json"

put()  { curl -fsS -X PUT  -H "$AUTH" -H "$CT" "$BASE/$1" -d "$2" >/dev/null && echo "  ~ $1"; }

echo "Creating database service local-files (CustomDatabase)..."
put "services/databaseServices" '{
  "name": "local-files",
  "serviceType": "CustomDatabase",
  "connection": {"config": {"type": "CustomDatabase", "sourcePythonClass": "n/a"}}
}'

echo "Creating database local-files.default..."
put "databases" '{
  "name": "default",
  "service": "local-files"
}'

echo "Creating schema local-files.default.default..."
put "databaseSchemas" '{
  "name": "default",
  "database": "local-files.default"
}'

echo "Creating tables..."
put "tables" '{
  "name": "sensor_readings",
  "databaseSchema": "local-files.default.default",
  "columns": [
    {"name": "sensor_id", "dataType": "STRING"},
    {"name": "metric_1",  "dataType": "DOUBLE"},
    {"name": "metric_2",  "dataType": "DOUBLE"},
    {"name": "ts",        "dataType": "STRING"}
  ]
}'

put "tables" '{
  "name": "sensor_profiles",
  "databaseSchema": "local-files.default.default",
  "columns": [
    {"name": "sensor_id",     "dataType": "STRING"},
    {"name": "avg_metric_1",  "dataType": "DOUBLE"},
    {"name": "avg_metric_2",  "dataType": "DOUBLE"},
    {"name": "confidence",    "dataType": "DOUBLE"}
  ]
}'

put "tables" '{
  "name": "zone_lookup",
  "databaseSchema": "local-files.default.default",
  "columns": [
    {"name": "bucket",     "dataType": "INT"},
    {"name": "zone_label", "dataType": "STRING"}
  ]
}'

put "tables" '{
  "name": "sensor_profiles_enriched",
  "databaseSchema": "local-files.default.default",
  "columns": [
    {"name": "sensor_id",     "dataType": "STRING"},
    {"name": "avg_metric_1",  "dataType": "DOUBLE"},
    {"name": "avg_metric_2",  "dataType": "DOUBLE"},
    {"name": "zone_label",    "dataType": "STRING"}
  ]
}'

echo "Done."
