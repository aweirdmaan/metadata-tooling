#!/usr/bin/env bash
# Fill in governance metadata that makes the POC look real:
# - Descriptions on every table, column, pipeline
# - Owners (admin)
# - Tiers
# - Tags (PII / Tier)
# - Tasks on the pipelines
#
# Required env: OMD_JWT
set -euo pipefail

BASE="http://localhost:8585/api/v1"
AUTH="Authorization: Bearer ${OMD_JWT:?OMD_JWT not set}"
CT_PATCH="Content-Type: application/json-patch+json"
CT_JSON="Content-Type: application/json"
ADMIN_ID=$(curl -fsS -H "$AUTH" "$BASE/users/name/admin" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")

patch() {
  local type=$1 fqn=$2 ops=$3
  curl -fsS -X PATCH -H "$AUTH" -H "$CT_PATCH" "$BASE/$type/name/$fqn" -d "$ops" >/dev/null && echo "  ~ $type/$fqn"
}

put_pipeline() {
  local name=$1 desc=$2 task_name=$3 task_desc=$4
  curl -fsS -X PUT -H "$AUTH" -H "$CT_JSON" "$BASE/pipelines" -d '{
    "name": "'"$name"'",
    "service": "spark-poc",
    "description": "'"$desc"'",
    "tasks": [
      {
        "name": "'"$task_name"'",
        "displayName": "'"$task_name"'",
        "description": "'"$task_desc"'",
        "taskType": "SparkJob"
      }
    ]
  }' >/dev/null && echo "  ~ pipelines/spark-poc.$name"
}

echo "Pipelines with descriptions + tasks..."
put_pipeline "build_sensor_profiles" \
  "Reads raw sensor readings (metric_1, metric_2 + timestamp) and aggregates per sensor_id to derive an average profile plus a confidence score (count(*)/100). Confidence is deliberately unclamped so downstream DQ checks can flag noise from high-volume sensors." \
  "aggregate_sensor_profile" \
  "groupBy(sensor_id).agg(avg(metric_1), avg(metric_2), count/100 as confidence). Writes sensor_profiles.parquet."

put_pipeline "enrich_with_zone_label" \
  "Joins sensor_profiles with a static zone_lookup table on floor(avg_metric_1) to label each sensor with a zone. Uses a LEFT join so out-of-range sensors land as 'unknown' rather than being dropped silently." \
  "join_zone_label" \
  "sensor_profiles LEFT JOIN zone_lookup ON floor(avg_metric_1).cast(int) = bucket, coalesce(zone_label, 'unknown'). Writes sensor_profiles_enriched.parquet."

echo "Updating tables (description + owner + tier + column descriptions)..."

patch tables local-files.default.default.sensor_readings '[
  {"op":"add","path":"/description","value":"Raw sensor reading events. Each row is one sample of (metric_1, metric_2) from a sensor at a point in time. Source feed; seeded with deliberate quality issues (some null sensor_ids and out-of-range metric_1 values) so downstream DQ checks have something to catch."},
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier3","source":"Classification","labelType":"Manual","state":"Confirmed"}]},
  {"op":"add","path":"/columns/0/description","value":"Unique sensor identifier. May be null in raw data (DQ checks should flag)."},
  {"op":"add","path":"/columns/1/description","value":"Primary sensor metric. Normal range 20..30; out-of-range values appear as noise."},
  {"op":"add","path":"/columns/2/description","value":"Secondary sensor metric. Typically 30..70."},
  {"op":"add","path":"/columns/3/description","value":"ISO-8601 timestamp of when the reading was recorded."}
]'

patch tables local-files.default.default.sensor_profiles '[
  {"op":"add","path":"/description","value":"Derived per-sensor profile. Each row aggregates many readings into a single (avg_metric_1, avg_metric_2) plus a confidence score driven by reading count. Two DQ tests attached: sensor_id never-null (Tier-1 invariant) and confidence in [0,1] (currently fails on high-volume sensors by design)."},
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier2","source":"Classification","labelType":"Manual","state":"Confirmed"}]},
  {"op":"add","path":"/columns/0/description","value":"Unique sensor identifier. Nulls filtered out upstream in BuildSensorProfiles."},
  {"op":"add","path":"/columns/1/description","value":"Average primary metric across all readings for this sensor."},
  {"op":"add","path":"/columns/2/description","value":"Average secondary metric across all readings for this sensor."},
  {"op":"add","path":"/columns/3/description","value":"count(*)/100.0. Unclamped on purpose: high-volume sensors land above 1.0 and trip the DQ range test."}
]'

patch tables local-files.default.default.zone_lookup '[
  {"op":"add","path":"/description","value":"Static reference table mapping integer bucket (floor of avg_metric_1) to a zone_label. Deliberately covers buckets 20..24 only so out-of-range readings land as zone_label=unknown via the LEFT join in EnrichWithZoneLabel."},
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier4","source":"Classification","labelType":"Manual","state":"Confirmed"}]},
  {"op":"add","path":"/columns/0/description","value":"Integer bucket of avg_metric_1. Join key against floor(avg_metric_1)."},
  {"op":"add","path":"/columns/1/description","value":"Human-readable zone label (zone_a..zone_e)."}
]'

patch tables local-files.default.default.sensor_profiles_enriched '[
  {"op":"add","path":"/description","value":"Consumer-facing dataset: per-sensor profile enriched with a zone label. The product of joining sensor_profiles to zone_lookup with a left join (unmatched buckets become unknown)."},
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier1","source":"Classification","labelType":"Manual","state":"Confirmed"}]},
  {"op":"add","path":"/columns/0/description","value":"Unique sensor identifier."},
  {"op":"add","path":"/columns/1/description","value":"Inherited from sensor_profiles.avg_metric_1."},
  {"op":"add","path":"/columns/2/description","value":"Inherited from sensor_profiles.avg_metric_2."},
  {"op":"add","path":"/columns/3/description","value":"Zone label for the sensor, or unknown if no bucket matched."}
]'

echo "Ownership + tier on pipelines..."
patch pipelines spark-poc.build_sensor_profiles '[
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier2","source":"Classification","labelType":"Manual","state":"Confirmed"}]}
]'
patch pipelines spark-poc.enrich_with_zone_label '[
  {"op":"add","path":"/owners","value":[{"id":"'"$ADMIN_ID"'","type":"user"}]},
  {"op":"add","path":"/tags","value":[{"tagFQN":"Tier.Tier1","source":"Classification","labelType":"Manual","state":"Confirmed"}]}
]'

echo "Pipeline service description..."
patch services/pipelineServices spark-poc '[
  {"op":"add","path":"/description","value":"Spark POC pipeline service. Houses the two Scala/Spark jobs that produce the sensor_profiles and sensor_profiles_enriched datasets. Lineage events emitted via the OpenMetadata Spark Agent."}
]'

echo "Done."
