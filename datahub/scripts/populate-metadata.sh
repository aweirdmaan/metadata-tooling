#!/usr/bin/env bash
# Bring DataHub up to parity with the OMD POC:
#   - 2 pipelines as DataFlow + DataJob (DataHub's pipeline model)
#   - Ownership on every entity (admin user)
#   - Tier tags via globalTags (Tier1..4)
#   - dataset profile stats (rowCount, columnCount, per-column null/distinct)
#   - Domain "spark-poc" assigned to all assets
set -euo pipefail

GMS="${DATAHUB_GMS:-http://localhost:8080}"
TOKEN="${DATAHUB_TOKEN:-}"
PI="spark_poc"
NOW_MS=$(($(date +%s) * 1000))
AUTH_HDR=""
[[ -n "$TOKEN" ]] && AUTH_HDR="Authorization: Bearer $TOKEN"
CT="Content-Type: application/json"

urn() { echo "urn:li:dataset:(urn:li:dataPlatform:file,${PI}.${1},PROD)"; }
OBS_URN=$(urn "sample-data.sensor_readings")
AL_URN=$(urn  "sample-data.zone_lookup")
HL_URN=$(urn  "tmp.sensor_profiles")
HD_URN=$(urn  "tmp.sensor_profiles_enriched")

FLOW_URN="urn:li:dataFlow:(spark,${PI}.spark-poc,PROD)"
JOB1_URN="urn:li:dataJob:(${FLOW_URN},build_sensor_profiles)"
JOB2_URN="urn:li:dataJob:(${FLOW_URN},enrich_with_zone_label)"
ADMIN_URN="urn:li:corpuser:datahub"
DOMAIN_URN="urn:li:domain:spark-poc"

put_aspect() {
  local entity=$1 entityType=$2 aspectName=$3 aspectJson=$4
  local valueStr
  valueStr=$(printf '%s' "$aspectJson" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  local payload='{"entityType":"'$entityType'","entityUrn":"'$entity'","aspectName":"'$aspectName'","changeType":"UPSERT","aspect":{"value":'"$valueStr"',"contentType":"application/json"}}'
  curl -fsS -X POST "$GMS/aspects?action=ingestProposal" \
    ${AUTH_HDR:+-H "$AUTH_HDR"} -H "$CT" \
    -d '{"proposal":'"$payload"'}' >/dev/null && echo "  ~ $entityType / $aspectName"
}

echo "== Domain =="
put_aspect "$DOMAIN_URN" domain domainProperties \
  '{"name":"spark-poc","description":"Synthetic sensor-reading pipeline used by the Spark POC."}'

echo "== DataFlow (pipeline service) =="
put_aspect "$FLOW_URN" dataFlow dataFlowInfo \
  '{"name":"spark-poc","description":"Spark POC pipeline service. Houses build_sensor_profiles and enrich_with_zone_label."}'
put_aspect "$FLOW_URN" dataFlow ownership \
  '{"owners":[{"owner":"'"$ADMIN_URN"'","type":"DATAOWNER"}],"lastModified":{"time":'"$NOW_MS"',"actor":"'"$ADMIN_URN"'"}}'
put_aspect "$FLOW_URN" dataFlow domains '{"domains":["'"$DOMAIN_URN"'"]}'

echo "== DataJobs (pipelines) =="
put_aspect "$JOB1_URN" dataJob dataJobInfo \
  '{"name":"build_sensor_profiles","description":"groupBy(sensor_id).agg(avg(metric_1), avg(metric_2), count/100 as confidence). Writes sensor_profiles.parquet. confidence is deliberately unclamped so downstream DQ checks can flag high-volume sensors.","type":{"string":"SPARK"}}'
put_aspect "$JOB1_URN" dataJob dataJobInputOutput \
  '{"inputDatasets":["'"$OBS_URN"'"],"outputDatasets":["'"$HL_URN"'"],"inputDatajobs":[]}'
put_aspect "$JOB1_URN" dataJob ownership \
  '{"owners":[{"owner":"'"$ADMIN_URN"'","type":"DATAOWNER"}],"lastModified":{"time":'"$NOW_MS"',"actor":"'"$ADMIN_URN"'"}}'
put_aspect "$JOB1_URN" dataJob globalTags '{"tags":[{"tag":"urn:li:tag:Tier2"}]}'

put_aspect "$JOB2_URN" dataJob dataJobInfo \
  '{"name":"enrich_with_zone_label","description":"sensor_profiles LEFT JOIN zone_lookup on floor(avg_metric_1).cast(int) = bucket, coalesce(zone_label, unknown). Writes sensor_profiles_enriched.parquet.","type":{"string":"SPARK"}}'
put_aspect "$JOB2_URN" dataJob dataJobInputOutput \
  '{"inputDatasets":["'"$HL_URN"'","'"$AL_URN"'"],"outputDatasets":["'"$HD_URN"'"],"inputDatajobs":["'"$JOB1_URN"'"]}'
put_aspect "$JOB2_URN" dataJob ownership \
  '{"owners":[{"owner":"'"$ADMIN_URN"'","type":"DATAOWNER"}],"lastModified":{"time":'"$NOW_MS"',"actor":"'"$ADMIN_URN"'"}}'
put_aspect "$JOB2_URN" dataJob globalTags '{"tags":[{"tag":"urn:li:tag:Tier1"}]}'

echo "== Dataset ownership + tier + domain =="
for pair in "$OBS_URN:Tier3" "$AL_URN:Tier4" "$HL_URN:Tier2" "$HD_URN:Tier1"; do
  urnv="${pair%:*}"
  tierv="${pair##*:}"
  put_aspect "$urnv" dataset ownership \
    '{"owners":[{"owner":"'"$ADMIN_URN"'","type":"DATAOWNER"}],"lastModified":{"time":'"$NOW_MS"',"actor":"'"$ADMIN_URN"'"}}'
  put_aspect "$urnv" dataset globalTags '{"tags":[{"tag":"urn:li:tag:'"$tierv"'"}]}'
  put_aspect "$urnv" dataset domains '{"domains":["'"$DOMAIN_URN"'"]}'
done

echo "== Dataset profiles (row counts + column stats) =="
put_aspect "$OBS_URN" dataset datasetProfile \
  '{"timestampMillis":'"$NOW_MS"',"rowCount":10151,"columnCount":4,"sizeInBytes":412300,"fieldProfiles":[
    {"fieldPath":"sensor_id","uniqueCount":4455,"nullCount":50,"nullProportion":0.005,"sampleValues":["sensor_01728","sensor_03608","sensor_hv_001"]},
    {"fieldPath":"metric_1","uniqueCount":9800,"nullCount":0,"min":"51.0","max":"94.1","mean":"52.3"},
    {"fieldPath":"metric_2","uniqueCount":9750,"nullCount":0,"min":"-0.3","max":"0.3","mean":"0.0"},
    {"fieldPath":"ts","nullCount":0}
  ]}'
put_aspect "$AL_URN" dataset datasetProfile \
  '{"timestampMillis":'"$NOW_MS"',"rowCount":5,"columnCount":2,"sizeInBytes":120,"fieldProfiles":[
    {"fieldPath":"bucket","uniqueCount":5,"nullCount":0,"min":"51","max":"55"},
    {"fieldPath":"zone_label","uniqueCount":5,"nullCount":0,"sampleValues":["zone_a","zone_b","zone_c","zone_d","zone_e"]}
  ]}'
put_aspect "$HL_URN" dataset datasetProfile \
  '{"timestampMillis":'"$NOW_MS"',"rowCount":4455,"columnCount":4,"sizeInBytes":178200,"fieldProfiles":[
    {"fieldPath":"sensor_id","uniqueCount":4455,"nullCount":0,"uniqueProportion":1.0},
    {"fieldPath":"avg_metric_1","uniqueCount":4455,"nullCount":0,"min":"51.00538","max":"66.07531","mean":"51.62"},
    {"fieldPath":"avg_metric_2","uniqueCount":4455,"nullCount":0},
    {"fieldPath":"confidence","uniqueCount":120,"nullCount":0,"min":"0.02","max":"2.2","mean":"0.023"}
  ]}'
put_aspect "$HD_URN" dataset datasetProfile \
  '{"timestampMillis":'"$NOW_MS"',"rowCount":4455,"columnCount":4,"sizeInBytes":196500,"fieldProfiles":[
    {"fieldPath":"sensor_id","uniqueCount":4455,"nullCount":0,"uniqueProportion":1.0},
    {"fieldPath":"avg_metric_1","nullCount":0,"min":"51.005","max":"66.075"},
    {"fieldPath":"avg_metric_2","nullCount":0},
    {"fieldPath":"zone_label","uniqueCount":6,"nullCount":0,"sampleValues":["zone_a","zone_b","zone_c","zone_d","unknown"]}
  ]}'

echo "Done."
