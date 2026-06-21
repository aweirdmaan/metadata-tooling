#!/usr/bin/env bash
# Push DataHub dataset URNs + lineage + Great-Expectations-style assertions
# via the DataHub OpenAPI v3 endpoint.
#
# DataHub identifies every entity with a URN. For local files we use:
#   urn:li:dataset:(urn:li:dataPlatform:file,spark_poc.<path>,PROD)
#
# Lineage is posted as UpstreamLineageAspect on each downstream dataset.
# DQ uses the AssertionResult / AssertionRunEvent aspects.
#
# Required env: DATAHUB_GMS (defaults to http://localhost:8080)
set -euo pipefail

GMS="${DATAHUB_GMS:-http://localhost:8080}"
TOKEN="${DATAHUB_TOKEN:-}"
PI="spark_poc"

CT="Content-Type: application/json"
AUTH_HDR=""
[[ -n "$TOKEN" ]] && AUTH_HDR="Authorization: Bearer $TOKEN"

urn() { echo "urn:li:dataset:(urn:li:dataPlatform:file,${PI}.${1},PROD)"; }
OBS_URN=$(urn "sample-data.sensor_readings")
AL_URN=$(urn  "sample-data.zone_lookup")
HL_URN=$(urn  "tmp.sensor_profiles")
HD_URN=$(urn  "tmp.sensor_profiles_enriched")

put_aspect() {
  local entity=$1 entityType=$2 aspectName=$3 aspectJson=$4
  # DataHub expects aspect.value as a JSON-encoded string, not raw JSON
  local valueStr
  valueStr=$(printf '%s' "$aspectJson" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  local payload='{"entityType":"'$entityType'","entityUrn":"'$entity'","aspectName":"'$aspectName'","changeType":"UPSERT","aspect":{"value":'"$valueStr"',"contentType":"application/json"}}'
  curl -fsS -X POST "$GMS/aspects?action=ingestProposal" \
    ${AUTH_HDR:+-H "$AUTH_HDR"} -H "$CT" \
    -d '{"proposal":'"$payload"'}' >/dev/null && echo "  ~ $entityType / $aspectName"
}

# --- Schemas + descriptions ----------------------------------------------------
echo "Posting datasetProperties + schemaMetadata..."

post_dataset() {
  local urn=$1 name=$2 desc=$3 fields=$4
  put_aspect "$urn" dataset datasetProperties \
    '{"name":"'"$name"'","description":"'"$desc"'","customProperties":{"poc":"datahub"}}'
  put_aspect "$urn" dataset schemaMetadata "$fields"
}

field() {
  local name=$1 type=$2 desc=$3
  echo '{"fieldPath":"'"$name"'","nativeDataType":"'"$type"'","type":{"type":{"com.linkedin.schema.'"$type"'Type":{}}},"description":"'"$desc"'"}'
}

schema_meta() {
  local urn=$1 platform=spark_poc
  local fields_json=$2
  echo '{"schemaName":"sensor_readings","platform":"urn:li:dataPlatform:file","version":0,"hash":"","platformSchema":{"com.linkedin.schema.OtherSchema":{"rawSchema":""}},"fields":['"$fields_json"']}'
}

post_dataset "$OBS_URN" "sensor_readings" \
  "Raw sensor readings. Seeded with deliberate nulls and out-of-range metric_1 values so downstream DQ has something to catch." \
  "$(schema_meta "$OBS_URN" "$(field sensor_id String 'Sensor ID; nullable in raw'),$(field metric_1 Number 'Primary metric reading'),$(field metric_2 Number 'Secondary metric reading'),$(field ts String 'Timestamp')")"

post_dataset "$AL_URN" "zone_lookup" \
  "Static reference: floor(metric_1) -> zone_label. Buckets 92-94 intentionally absent." \
  "$(schema_meta "$AL_URN" "$(field bucket Number 'Floor of latitude'),$(field zone_label String 'Zone label')")"

post_dataset "$HL_URN" "sensor_profiles" \
  "Per-sensor profile. confidence = count(*)/100 - unclamped, so high-volume sensors trip the downstream range check." \
  "$(schema_meta "$HL_URN" "$(field sensor_id String 'Sensor ID'),$(field avg_metric_1 Number 'Average primary metric'),$(field avg_metric_2 Number 'Average secondary metric'),$(field confidence Number 'count(*)/100 (unclamped)')")"

post_dataset "$HD_URN" "sensor_profiles_enriched" \
  "sensor_profiles left-joined to zone_lookup; unmatched buckets land as unknown." \
  "$(schema_meta "$HD_URN" "$(field sensor_id String 'Sensor ID'),$(field avg_metric_1 Number 'Average primary metric'),$(field avg_metric_2 Number 'Average secondary metric'),$(field zone_label String 'Zone label (unknown if no bucket match)')")"

# --- Lineage edges -------------------------------------------------------------
echo "Posting lineage edges..."

upstream() {
  local downstream_urn=$1; shift
  local upstreams=""
  for u in "$@"; do
    upstreams="${upstreams:+$upstreams,}{\"auditStamp\":{\"time\":$(($(date +%s)*1000)),\"actor\":\"urn:li:corpuser:datahub\"},\"dataset\":\"$u\",\"type\":\"TRANSFORMED\"}"
  done
  put_aspect "$downstream_urn" dataset upstreamLineage \
    '{"upstreams":['"$upstreams"']}'
}

upstream "$HL_URN" "$OBS_URN"
upstream "$HD_URN" "$HL_URN" "$AL_URN"

# --- DQ assertions -------------------------------------------------------------
echo "Posting DQ assertions on sensor_profiles..."

# Assertion 1: sensor_id NOT NULL on sensor_profiles -> Success
A1="urn:li:assertion:sensor_profiles_sensor_id_not_null"
put_aspect "$A1" assertion assertionInfo '{
  "type":"DATASET",
  "datasetAssertion":{
    "dataset":"'"$HL_URN"'",
    "scope":"DATASET_COLUMN",
    "fields":["urn:li:schemaField:('"$HL_URN"',sensor_id)"],
    "aggregation":"IDENTITY",
    "operator":"NOT_NULL"
  },
  "source":{"type":"NATIVE","created":{"time":'$(($(date +%s)*1000))',"actor":"urn:li:corpuser:datahub"}}
}'
put_aspect "$A1" assertion assertionRunEvent '{
  "timestampMillis":'$(($(date +%s)*1000))',
  "runId":"manual-'$(date +%s)'",
  "asserteeUrn":"'"$HL_URN"'",
  "status":"COMPLETE",
  "result":{"type":"SUCCESS","externalUrl":"","nativeResults":{"observed":"0","total":"4455"}}
}'

# Assertion 2: confidence BETWEEN 0 AND 1 -> Failure (5 violating rows)
A2="urn:li:assertion:sensor_profiles_confidence_in_range"
put_aspect "$A2" assertion assertionInfo '{
  "type":"DATASET",
  "datasetAssertion":{
    "dataset":"'"$HL_URN"'",
    "scope":"DATASET_COLUMN",
    "fields":["urn:li:schemaField:('"$HL_URN"',confidence)"],
    "aggregation":"IDENTITY",
    "operator":"BETWEEN",
    "parameters":{"minValue":{"value":"0","type":"NUMBER"},"maxValue":{"value":"1","type":"NUMBER"}}
  },
  "source":{"type":"NATIVE","created":{"time":'$(($(date +%s)*1000))',"actor":"urn:li:corpuser:datahub"}}
}'
put_aspect "$A2" assertion assertionRunEvent '{
  "timestampMillis":'$(($(date +%s)*1000))',
  "runId":"manual-'$(date +%s)'",
  "asserteeUrn":"'"$HL_URN"'",
  "status":"COMPLETE",
  "result":{"type":"FAILURE","externalUrl":"","nativeResults":{"observedMin":"0.02","observedMax":"2.2","outOfRangeRows":"5"}}
}'

echo "Done."
