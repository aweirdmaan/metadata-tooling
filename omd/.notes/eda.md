# OMD POC — EDA notes

Date: 2026-05-28 · Issue: omd-a34.1

## Stack (Q1)

- Use official `docker-compose-postgres.yml` from OMD **1.12.x** release (jumped past 1.6 since we last looked).
- Four mandatory containers: `openmetadata-server`, `postgresql`, `elasticsearch`, `openmetadata-ingestion` (embedded Airflow).
- UI: http://localhost:8585 — `admin@open-metadata.org` / `admin`. Airflow: http://localhost:8080 — `admin`/`admin`.
- Allocate ≥ 6 GiB / 4 vCPUs to Docker Desktop. If ES restart-loops, set `ES_JAVA_OPTS=-Xms1g -Xmx1g`.
- Apple Silicon: OMD images are multi-arch — no platform override needed for OMD containers. Only override if adding non-OMD sidecars (some MinIO tags).

## Lineage capture (Q2)

**Choice: OpenMetadata Spark Agent** (OMD's fork of the OpenLineage Spark listener).

- One fat jar: `openmetadata-spark-agent.jar` from `open-metadata/openmetadata-spark-agent` releases. Spark 3.1+.
- Six Spark conf entries:
  - `spark.extraListeners=io.openlineage.spark.agent.OpenLineageSparkListener`
  - `spark.openmetadata.transport.type=openmetadata`
  - `spark.openmetadata.transport.hostPort=http://host.docker.internal:8585/api`
  - `spark.openmetadata.transport.jwtToken=<bot-token>`
  - `spark.openmetadata.transport.pipelineServiceName=spark-poc`
  - `spark.openmetadata.transport.pipelineName=<job-name>`
  - Optional: `spark.openmetadata.transport.databaseServiceNames=local-files` to scope source resolution
- Produces: Pipeline Service + Pipeline entity + **table→table lineage edges** automatically.
- Prereq for source tables to resolve: ingest a "Local Files" (or MinIO) connector first so the parquet/CSV tables exist as entities.

Rejected:
- Vanilla OpenLineage listener — works (OMD accepts OL events) but marginally more wiring; only pick if fan-out to Marquez is needed.
- `metadata ingest` Spark connector — ingests job *catalog*, not runtime read/write edges. Doesn't satisfy lineage demo.
- Manual `/api/v1/lineage` POST — last-resort fallback.

## Data Quality (Q3)

**Choice: UI-driven Test Cases**, no custom runner.

- Add Test Cases from each table's Data Quality tab → embedded Airflow generates a DAG and runs it on schedule.
- Built-in tests we'll use:
  - `columnValuesToBeNotNull(sensor_id)` → **green** (seeded clean column)
  - `columnValuesToBeBetween(confidence, 0, 1)` → **red** (seed one out-of-range row)
  - `tableRowCountToEqual` → optional second red on downstream joined table
- Results: timestamped per execution, browsable in Data Quality tab + Profiler/Health view, status badge on the table's node in the lineage graph (but no overlay on edges).
- Same Test Suite can be encoded in YAML and run via `metadata test`, or POSTed to Test Suite API — defer to that only if the UI flow proves limiting.

## Dashboards (Q4)

OMD has **no native chart builder for arbitrary metrics**. Two surfaces available:

1. **Built-in Data Insights** — OMD-rendered governance dashboard (asset coverage, ownership, tier, DQ pass-rate over time, lineage coverage). Zero extra containers. **This carries the "dashboard" demo.**
2. **External Dashboard Service** — Superset / Metabase / Tableau / Looker etc. registered via connector. Catalogs external dashboards and stitches them into lineage as a third hop (table → chart).

**Plan:** lean on Data Insights for the governance/DQ-rollup demo. Optionally bolt on **Superset** as a stretch goal to demonstrate the third lineage hop.

## Sample data (Q5)

Three tables, two lineage hops, DQ at every level:

| Table | Format | Columns | Source |
|---|---|---|---|
| `sensor_readings` | CSV (raw) | `sensor_id, metric_1, metric_2, ts` | seeded; ~10k rows; some nulls + out-of-range metric_1 |
| `sensor_profiles` | Parquet | `sensor_id, avg_metric_1, avg_metric_2, confidence` | `groupBy(sensor_id).agg(avg(metric_1), avg(metric_2), count→confidence_proxy)` over sensor_readings |
| `sensor_profiles_enriched` | Parquet | `sensor_id, avg_metric_1, avg_metric_2, zone_label` | join `sensor_profiles` with static `zone_lookup.csv` |

Lineage edges produced: `sensor_readings → sensor_profiles → sensor_profiles_enriched`, plus incidental `zone_lookup → sensor_profiles_enriched`.

DQ attach plan:
- `sensor_readings`: `columnValuesToBeNotNull(sensor_id)` (green if cleaned, red if raw)
- `sensor_profiles`: `columnValuesToBeBetween(confidence, 0, 1)` (red — by design)
- `sensor_profiles_enriched`: `tableRowCountToEqual(N)` (green or red depending on join)

## Mapping demo target → OMD primitive

| Demo target | OMD primitive | POC mechanism |
|---|---|---|
| Lineage | Pipeline + table→table edges | OMD Spark Agent listener, jar + 6 Spark conf entries |
| DQ | Test Suite + Test Case results on table entities | UI-added test cases, embedded Airflow runner |
| Dashboard | Built-in Data Insights views | Out-of-the-box once entities + DQ exist; optionally Superset as a registered Dashboard Service |

## Goal candidates (INVEST drafted — for refinement on the umbrella)

### Goal A — End-to-end lineage from raw CSV through two Spark jobs to derived tables, visible in OMD UI

- **WHY:** Lineage is the most visually impressive OMD capability and the easiest to fail to demonstrate (a job that writes correctly but produces no lineage edges teaches you nothing). Proving the listener works end-to-end is the foundation everything else stands on.
- **WHAT (acceptance):**
  1. OMD UI shows a Pipeline Service `spark-poc` with two Pipelines (`build_sensor_profiles`, `enrich_with_zone_label`).
  2. The lineage graph for `sensor_profiles_enriched` shows two upstream hops: `sensor_profiles` ← `sensor_readings` and `sensor_profiles` + `zone_lookup` → `sensor_profiles_enriched`.
  3. Column-level lineage is present on at least one edge.
- **INVEST:** ✅ Independent (one Spark job + listener wiring), Negotiable (which two jobs is open), Valuable (the headline demo), Estimable (~1 day), Small (one PR with two jobs + compose), Testable (UI screenshot OR API call to `/api/v1/lineage`).

### Goal B — At least one passing and one failing DQ check attached to a table, browsable in OMD

- **WHY:** A demo that only shows green checks fails to convey DQ value; the contrast between pass and fail is what sells the surface.
- **WHAT (acceptance):**
  1. `sensor_profiles` has at least 2 Test Cases configured via the UI.
  2. Test runs produce a mix: one green (`columnValuesToBeNotNull(sensor_id)`) and one red (`columnValuesToBeBetween(confidence, 0, 1)` with seeded out-of-range data).
  3. The table's node in the lineage view shows a DQ status badge reflecting failure.
- **INVEST:** ✅ Independent of Goal A's listener internals (depends only on the table existing as an entity), Negotiable (which tests), Valuable, Estimable (~half day), Small, Testable (status visible in UI + queryable via Test Suite API).

### Goal C — Governance dashboard surfacing the POC's assets

- **WHY:** The "dashboard" ask is the broadest — we need a visual rollup of the POC's metadata (assets, DQ pass-rate, lineage coverage) to land the story that OMD is not just a catalog but an observability surface.
- **WHAT (acceptance):**
  1. OMD's Data Insights surface shows non-zero values for: total assets, tier coverage, ownership coverage, DQ pass-rate.
  2. The POC's three tables appear with owners and tiers assigned.
  3. (Stretch) Superset is registered as a Dashboard Service and one chart from Superset appears as a downstream node in the lineage graph.
- **INVEST:** ✅ Independent (depends on entities+DQ existing, but doesn't touch Spark code), Negotiable (stretch is optional), Valuable, Estimable, Small (config + ownership/tier assignment + optionally Superset), Testable (UI rendering + non-zero metrics).

## Open questions for the lead

1. Is Superset's third-hop lineage worth including, or is built-in Data Insights enough to call the dashboard goal done?
2. Do we want a single Scala module with two `SparkMain` entry points, or two modules sharing a common dataset library? (Recommendation: single module, simpler for POC.)
3. Run Spark how? `spark-submit` from host? Inside a `spark` container in the same compose? `sbt run`? (Recommendation: `sbt run` from host, talking to `localhost:8585` — simplest, no container plumbing for the Spark side.)
4. JWT bot token — OMD generates an "ingestion-bot" token by default. Use that, or create a dedicated POC bot?
