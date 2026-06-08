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
JAVA_HOME=/opt/homebrew/opt/openjdk@21 sbt 'runMain com.poc.datahub.BuildSensorProfiles \
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

Six component tests cover both jobs' logic (no OMD stack required).

## 5. Run the second Spark job (Acceptance item 1)

Run `BuildSensorProfiles` first (step 4) to produce `sensor_profiles.parquet`, then:

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21 sbt 'runMain com.poc.datahub.EnrichWithZoneLabel \
  --sensor-profiles-path /tmp/sensor_profiles.parquet \
  --zone-lookup-path sample-data/zone_lookup.csv \
  --output-path /tmp/sensor_profiles_enriched.parquet'
```

The job reads `sensor_profiles.parquet`, left-joins with `zone_lookup.csv` on `floor(avg_metric_1)` matching `bucket`, fills unmatched rows with `zone_label = "unknown"`, and writes `sensor_profiles_enriched.parquet`.

## 6. Verify second lineage hop in the OMD UI (Acceptance items 2, 3, 4)

### Acceptance item 2 — Pipeline entity for the second job

1. In OMD UI: **Pipeline Services** → `spark-poc`
2. You should now see a second Pipeline entity named **`enrich_with_zone_label`** alongside `build_sensor_profiles`

### Acceptance item 3 — Two upstream edges on `sensor_profiles_enriched`

1. Navigate to the `sensor_profiles_enriched` table (search by name or browse under `local-files`)
2. Click the **Lineage** tab
3. The graph should show two upstream nodes: `sensor_profiles` and `zone_lookup`, both with edges pointing to `sensor_profiles_enriched`

### Acceptance item 4 — Column-level lineage

1. On the same Lineage tab, click an edge between the table nodes
2. The column-level panel should show at least one column mapping (e.g. `sensor_id` → `sensor_id`, or `avg_metric_1` → `avg_metric_1`)

## 7. Add DQ test cases via the OMD UI (Acceptance items 5, 6, 7)

These test cases are configured entirely through the UI — no code changes required.

### Add the passing test — `columnValuesToBeNotNull` on `sensor_id`

1. Navigate to the `sensor_profiles` table in OMD UI
2. Click the **Data Quality** tab
3. Click **Add Test** (or "Add Test Case")
4. Select test type: **`columnValuesToBeNotNull`**
5. Select column: **`sensor_id`**
6. Save and run the test suite

Expected result: **green** — `sensor_id` is always populated in `sensor_profiles` (nulls were filtered in `BuildSensorProfiles`).

### Add the failing test — `columnValuesToBeBetween` on `confidence`

1. On the same **Data Quality** tab, click **Add Test**
2. Select test type: **`columnValuesToBeBetween`**
3. Select column: **`confidence`**, set min = `0`, max = `1`
4. Save and run the test suite

Expected result: **red** — `confidence = count(*)/100.0` is unclamped; high-volume sensors (`sensor_hv_*`) accumulate counts > 100, producing confidence > 1.0.

### Observe the DQ status badge in the lineage view

1. Navigate to **Lineage** on the `sensor_profiles` table
2. The table's node in the lineage graph should display a **red DQ status badge** reflecting the failing test
3. The Data Quality tab shows both results side-by-side: one green, one red

## 8. Curate metadata for the governance dashboard (Acceptance items 8, 9, 10)

OMD's **Data Insights** surface (Settings → Data Insights, or the home dashboard) renders a governance dashboard automatically once entities, ownership, tiers, and DQ results are in place. To bring the metrics off zero:

### Assign Owners and Tiers to the three POC tables

For each of `sensor_readings`, `sensor_profiles`, `sensor_profiles_enriched`:

1. Open the table in OMD UI
2. **Owners** panel → assign yourself (or the `admin` user)
3. **Tier** panel → set `Tier1` for `sensor_profiles_enriched` (the consumer-facing output), `Tier2` for `sensor_profiles` (derived intermediate), `Tier3` for `sensor_readings` (raw)

### Add a description to the umbrella

The two Pipeline entities (`build_sensor_profiles`, `enrich_with_zone_label`) live under the `spark-poc` Pipeline Service. Open each pipeline → **Description** → add a short markdown blurb naming the input/output tables (one sentence each). This populates the lineage panel's hover cards.

### Verify Data Insights renders non-zero

1. Navigate to **Insights** in the left nav (or **Settings → Data Insights**)
2. The following should now read above zero:
   - Total assets: 3 (tables) + 2 (pipelines) + 1 (pipeline service)
   - Tier coverage: 3/3 tables tiered
   - Ownership coverage: 3/3 tables with owners
   - DQ pass rate: ~50% (one green, one red on `sensor_profiles`)
   - Lineage coverage: edges present between all three tables

The Data Insights view is OMD-rendered — no external BI tool needed. The Superset stretch (a fourth lineage hop into an external chart) is tracked separately and is not required for Goal C acceptance.

## What this POC demonstrates

- **Lineage:** raw CSV → first derived table → second derived table, plus an incidental edge from a static lookup. Two Pipeline entities under one Pipeline Service. Column-level lineage at every hop.
- **Data quality:** UI-driven Test Cases with a deliberate green + red mix. Status visible on the table node in the lineage graph.
- **Dashboards:** OMD's built-in Data Insights surface, populated by curated metadata (owners, tiers, descriptions) over the POC's assets.

Walking a viewer through these three surfaces — open the lineage graph, hover the DQ badge, click into Insights — is the elevator pitch this POC was built to support.
