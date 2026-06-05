# Open Data Discovery (ODD)

A read on what ODD is, what it does, and where the model gets in the way.

---

## What it is

A small, self-hosted metadata platform built around an open specification. The actual product, in the strongest sense, is the **ODD Spec** — a JSON Schema that defines how any tool can describe its data entities so that any other tool can ingest them. The **ODD Platform** is one reference implementation of a consumer; it provides a catalog UI and an ingestion endpoint that accepts ODD-shaped payloads.

The stack is deliberately lean: a Java Spring backend and a Postgres database. Two containers. No Kafka, no graph store, no Elasticsearch. Search is full-text inside Postgres. The whole platform comes up in a few minutes on a developer laptop.

Producers — called **collectors** — run as separate processes outside the platform. They scrape source systems (databases, dashboards, ML platforms, message queues) and POST ODD-Spec payloads to the platform's ingestion API. There are ODD collectors for Snowflake, Postgres, MySQL, Tableau, Kafka, Airflow, and a handful of others; a Spark collector exists but its scope is narrower than what OMD or DataHub offer.

## How the model is shaped

Everything is a **DataEntity**. Each entity has a globally unique **OddRN** (Open Data Discovery Resource Name), a `type` from a fixed enum, and one or more typed payload blocks that depend on the type. There are no aspects in the DataHub sense — entities are monolithic — but the payload shape varies by entity type.

The shape:

| Field | Meaning |
|---|---|
| `oddrn` | Path-style identifier — e.g. `//snowflake/host/abc/databases/prod/schemas/public/tables/users` |
| `name` | Display name |
| `description` | Markdown blurb |
| `type` | One of FILE, TABLE, VIEW, JOB_RUN, KAFKA_TOPIC, ML_MODEL, DASHBOARD, MICROSERVICE, etc. |
| `data_source_oddrn` | Parent data source under which this entity lives |
| `dataset` | Optional block: `field_list` with column schema |
| `data_transformer` | Optional block: `inputs`, `outputs` — describes a pipeline-shaped relationship |
| `data_consumer` | Optional block: `inputs` — describes a dashboard or report that reads data |
| `metadata` | Optional schema-tagged extension blocks |

Lineage is implicit — it falls out of the `data_transformer.inputs` and `data_consumer.inputs` blocks on existing entities. There's no separate `lineage` API; declaring an entity as a transformer of two inputs is how the edge gets created.

## What it does

### Search and discovery

Full-text search backed by Postgres `tsvector` indexes. The UI offers facets by data source, owner, tag, and type. Each entity has a single page with description, schema (if a `dataset` block exists), upstreams and downstreams (from transformer blocks), owners, tags, and metadata extensions. Not as fast or flexible as Elasticsearch-backed search, but enough for the platform's scope.

A **Terms** dictionary works as ODD's glossary equivalent — searchable business vocabulary attached to entities or columns.

### Lineage

Table-level lineage everywhere; **no column-level lineage** in the open-source platform's default rendering. Edges come from one place: the `data_transformer.inputs` and `data_consumer.inputs` blocks on entities. The UI walks the graph and shows the result.

The simplicity is the design. ODD doesn't have a runtime agent comparable to OMD's Spark Agent or DataHub's `acryl-spark-lineage` — there's an `odd-collector` for Spark but its scope is narrower (job catalog rather than fine-grained read/write capture). For Spark lineage at the level OMD and DataHub offer, the pragmatic path is to POST the lineage directly via the ingestion API from a wrapper script.

### Data quality (limited)

This is where ODD's model is thinnest. The fixed DataEntity type enum doesn't include `DATA_QUALITY_TEST` as a first-class type. Test results land under the `JOB_RUN` entity type with a `data_quality_test_run` payload block — but this requires the test entity itself (which the run references via `data_quality_test_oddrn`) to exist as a separately-defined entity, which the enum doesn't directly support.

In practice, ODD's DQ story works by ingesting from external runners (Great Expectations is the documented integration) which produce test definitions and runs in a shape ODD knows how to render. The platform doesn't author tests itself; it catalogues them.

### Governance

- **Owners** managed via a separate `/api/owners` API; attached to entities by ID through entity-edit endpoints.
- **Tags** likewise — defined globally and applied to entities.
- **Terms** — the glossary equivalent, hierarchical.
- **No tier system** baked in like DataHub's `urn:li:tag:Tier1`; tiering, if needed, is a tag-naming convention.
- **No domains** in the OMD / DataHub sense; ODD has a flatter structure organized around data sources.

### Insights

ODD's "Activity" view and a small set of dashboards (entity counts, owner coverage, data source health) are built into the UI. There's no built-in BI / chart builder; for richer analytics, point an external tool at the Postgres database directly.

### Collectors

About 30 source collectors maintained by the ODD community covering common warehouses, file stores, dashboards, and streaming systems. Each collector is a standalone process (typically Python, sometimes Java) configured via YAML and run on a schedule with cron, Airflow, or systemd. Collectors POST ODD-spec payloads to the platform's `/ingestion/entities` endpoint.

### Auth and access

The default ODD Platform has **no authentication** — anyone reaching the port can read and write. Production setups front it with an OIDC proxy or use the recently-added basic auth feature. Collectors authenticate with tokens scoped to a specific data source.

## What it doesn't do

- **No first-class pipeline entity.** The enum has `JOB_RUN` but no `JOB` type. Pipelines are inferred from `data_transformer.inputs` on the output entities, not modelled as standalone navigable assets. The OMD / DataHub experience of clicking into a pipeline and seeing its history doesn't translate directly.
- **No first-class DQ test entity.** Tests come in via the GX integration or via JOB_RUN entities with a `data_quality_test_run` block, but the platform doesn't natively author them.
- **No column-level lineage** in the default UI rendering.
- **No event-bus / streaming changes** like DataHub. Changes are HTTP-pushed by collectors on a schedule.
- **No webhook / alerting layer** baked in. Integrations exist (some collectors emit Slack notifications) but the platform itself doesn't notify on changes.
- **Smaller connector library** than OMD (~80) or DataHub (~80+). ODD covers the common cases but the long tail is thinner.

## What surprised in this POC

- **The ingestion endpoint requires a DataSource to exist first**, with the exact OddRN referenced by the entities. Posting entities under `//file/host/local` returns 404 "DataSource not found" until that source is registered via `POST /api/datasources`.
- **The data source registration returns its own token** that's different from the collector token created via Management → Collectors. The data source token is the one that authorises entity pushes under that source.
- **DataEntityType is a closed enum.** Inventing types like `DATA_QUALITY_TEST_RUN` returns a 500 with `Cannot construct instance of DataEntityType, problem: Unexpected value`. The valid types are: API_CALL, API_SERVICE, DASHBOARD, DATABASE_SERVICE, ENTITY_RELATIONSHIP, FEATURE_GROUP, FILE, GRAPH_NODE, GRAPH_RELATIONSHIP, JOB_RUN, KAFKA_SERVICE, KAFKA_TOPIC, MICROSERVICE, ML_EXPERIMENT, ML_MODEL, ML_MODEL_TRAINING, TABLE, UNKNOWN, VECTOR_STORE, VIEW.
- **JOB_RUN entities need a parent transformer that exists.** Posting a JOB_RUN whose `transformer_oddrn` doesn't resolve fails with a Postgres foreign-key violation. This is one of the places the model assumes a pre-existing job system (Airflow, etc.) the platform is just observing.
- **The official `demo.yaml` is bigger than needed.** It includes injector and sample-postgres services that require external `../injector` mounts. A minimal compose with just `database` + `odd-platform` is enough to run the platform.
- **Port 8080 conflicts** with DataHub's GMS when running multiple catalogs side by side. Remap to 8090 (or any other) in the compose `ports` block.

## Where it fits

ODD makes a different bet than OMD or DataHub. The product is the **spec**, not the platform. That changes who it's for:

- A small organisation that wants a catalog + lineage without operating Kafka, MySQL, Neo4j, and a handful of JVM services — ODD's two-container stack is the lightest credible option.
- A platform team building infrastructure that needs to interop with a metadata standard — adopting the ODD Spec gives you a stable interchange format and a reference consumer for free.
- An environment where the catalog UX is secondary and the priority is feeding metadata cleanly between systems — ODD's spec-first design favours that.

It's a less polished fit than OMD or DataHub when the UI is the primary deliverable, when DQ needs to be authored inside the catalog, or when many independent producers need write decoupling.

## Running it

The POC at `pocs/odd`:

- `docker compose up -d` brings up Postgres on 5532 and the ODD Platform UI on 8090.
- In the UI, create a Collector under **Management → Collectors**, copy its token. Then `POST /api/datasources` to register a DataSource — the response returns a separate token specific to that source.
- `scripts/seed-odd.sh` (with `ODD_TOKEN=<data-source-token>`) posts the four data entities (sensor_readings, zone_lookup, sensor_profiles, sensor_profiles_enriched) including the `data_transformer.inputs` blocks that create the lineage edges.
- `scripts/populate-metadata.sh` attempts to add JOB_RUN entities for pipelines and DQ test runs — partially limited by ODD's data model.

End state: 4 data entities visible in the Catalog tab with lineage between them. Pipeline and DQ surfaces are thinner than OMD or DataHub — a real product characteristic, not a wiring gap.
