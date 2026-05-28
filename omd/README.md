# OMD POC

OpenMetadata local stack + Spark job demonstrating lineage from a raw CSV to a derived parquet table.

## Prerequisites

- Docker Desktop (≥ 6 GiB / 4 vCPUs allocated)
- Java 21 (`JAVA_HOME=/opt/homebrew/opt/openjdk@21`)
- sbt 1.12.11

> Complete steps 1 and 2 below before any `sbt` commands — `build.sbt` references `lib/openmetadata-spark-agent-1.1.jar` as an unmanaged dependency.

## 1. Start the OMD stack (Acceptance item 1)

```bash
docker compose up -d
```

Wait ~2 minutes for all four containers to become healthy. Then open:

- **OMD UI:** http://localhost:8585 — log in with `admin@open-metadata.org` / `admin`
- **Airflow:** http://localhost:8080 — `admin` / `admin`

If Elasticsearch restart-loops, it usually means Docker Desktop has insufficient memory. Increase to ≥ 6 GiB in Docker Desktop → Settings → Resources.

## 2. Download the OMD Spark Agent jar

```bash
curl -L -o lib/openmetadata-spark-agent-1.1.jar \
  https://github.com/open-metadata/openmetadata-spark-agent/releases/download/1.1/openmetadata-spark-agent-1.1.jar
```

## 3. Get the JWT token

In the OMD UI: **Settings → Bots → ingestion-bot → copy token**

```bash
export OMD_JWT=<paste-token-here>
```

## 4. Run the Spark job (Acceptance item 2)

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21 sbt 'runMain com.poc.omd.BuildSensorProfiles \
  --input-path sample-data/sensor_readings.csv \
  --output-path /tmp/sensor_profiles.parquet'
```

The job reads `sensor_readings.csv`, groups by `sensor_id`, computes average metric_1/metric_2 and `confidence = count(*)/100.0`, and writes `sensor_profiles.parquet`.

## 5. Verify lineage in the OMD UI

### Acceptance item 3 — Pipeline Service and Pipeline entity

1. In OMD UI: **Pipeline Services** (left nav) → look for a service named **`spark-poc`**
2. Click into it → you should see a Pipeline entity named **`build_sensor_profiles`**

### Acceptance item 4 — Lineage edge: sensor_readings → sensor_profiles

1. Navigate to the `sensor_profiles` table (under the `local-files` database service, or search by name)
2. Click the **Lineage** tab
3. The graph should show an upstream node `sensor_readings` with an edge pointing to `sensor_profiles`

### Acceptance item 5 — Column-level lineage

1. On the same Lineage tab, click an edge between the two table nodes
2. The column-level lineage panel should show at least one column mapping (e.g. `metric_1` → `avg_metric_1`, or `sensor_id` → `sensor_id`)

## Running tests

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21 sbt test
```

Three component tests cover the aggregation logic (no OMD stack required).
