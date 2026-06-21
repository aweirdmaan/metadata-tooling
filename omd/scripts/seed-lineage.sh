#!/usr/bin/env bash
# Seed lineage edges between the POC tables, attributed to the Pipeline entities.
# Mirrors what the OMD Spark Agent would have produced if its auto-link against
# locationPath had matched.
#
# Required env: OMD_JWT
set -euo pipefail

BASE="http://localhost:8585/api/v1"
AUTH="Authorization: Bearer ${OMD_JWT:?OMD_JWT not set}"
CT="Content-Type: application/json"

get_id() {
  local type=$1 fqn=$2
  curl -fsS -H "$AUTH" "$BASE/$type/name/$fqn" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])"
}

OBS_ID=$(get_id tables local-files.default.default.sensor_readings)
HL_ID=$(get_id tables local-files.default.default.sensor_profiles)
AL_ID=$(get_id tables local-files.default.default.zone_lookup)
HD_ID=$(get_id tables local-files.default.default.sensor_profiles_enriched)
P1_ID=$(get_id pipelines spark-poc.build_sensor_profiles)
P2_ID=$(get_id pipelines spark-poc.enrich_with_zone_label)

echo "ids: readings=$OBS_ID profiles=$HL_ID lookup=$AL_ID enriched=$HD_ID p1=$P1_ID p2=$P2_ID"

add_edge() {
  local from_id=$1 from_type=$2 to_id=$3 to_type=$4 pipeline_id=$5 desc=$6
  local payload='{"edge":{"fromEntity":{"id":"'$from_id'","type":"'$from_type'"},"toEntity":{"id":"'$to_id'","type":"'$to_type'"},"lineageDetails":{"pipeline":{"id":"'$pipeline_id'","type":"pipeline"},"description":"'$desc'"}}}'
  curl -fsS -X PUT -H "$AUTH" -H "$CT" "$BASE/lineage" -d "$payload" >/dev/null && echo "  edge: $desc"
}

echo "Adding lineage edges..."
add_edge "$OBS_ID" table "$HL_ID" table "$P1_ID" "sensor_readings -> sensor_profiles via BuildSensorProfiles"
add_edge "$HL_ID" table "$HD_ID" table "$P2_ID" "sensor_profiles -> sensor_profiles_enriched via EnrichWithZoneLabel"
add_edge "$AL_ID" table "$HD_ID" table "$P2_ID" "zone_lookup -> sensor_profiles_enriched via EnrichWithZoneLabel"

echo "Done."
