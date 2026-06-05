# Open Data Discovery — the domain model

Smaller surface than OMD or DataHub, by design.

## The core idea

ODD's product is the **specification** more than the platform. The spec defines a fixed shape for metadata: every asset becomes a **DataEntity** with a globally unique **OddRN**, a `type` from a closed enum, and one or more typed payload blocks depending on type. Any producer that emits this shape can be ingested by any consumer that accepts it. The ODD Platform is one such consumer.

The entire model fits in one paragraph: a DataEntity belongs to a DataSource, references its fields in a `dataset` block (if it has a schema), and declares relationships to other entities via `data_transformer` (it transforms these inputs into outputs) or `data_consumer` (it consumes these inputs to produce a report or dashboard). Lineage falls out of those relationship blocks. Owners, tags, and terms are separate entities that get linked back via the management API. That's the whole graph.

## The OddRN

A path-style identifier:

| Example | Meaning |
|---|---|
| `//snowflake/host/abc.snowflakecomputing.com/databases/prod/schemas/public/tables/users` | A Snowflake table |
| `//airflow/host/airflow.internal/dags/etl_users` | An Airflow DAG |
| `//file/host/local/path/tmp/sensor_readings.parquet` | A local parquet file |
| `//kafka/host/broker.example.com/topics/events` | A Kafka topic |

The OddRN is the identity — entities don't get a UUID, the OddRN is the primary key. Producers construct OddRNs deterministically from the source system's own identifiers, which means two collectors hitting the same source produce identical OddRNs and the platform naturally de-duplicates.

## DataEntityType — a closed enum

The full list of valid types:

| Category | Types |
|---|---|
| Tabular data | TABLE, VIEW, FILE, FEATURE_GROUP, VECTOR_STORE |
| Pipelines / jobs | JOB_RUN |
| Streaming | KAFKA_TOPIC, KAFKA_SERVICE |
| Services | API_CALL, API_SERVICE, MICROSERVICE, DATABASE_SERVICE |
| Dashboards | DASHBOARD |
| ML | ML_MODEL, ML_MODEL_TRAINING, ML_EXPERIMENT |
| Graph | GRAPH_NODE, GRAPH_RELATIONSHIP, ENTITY_RELATIONSHIP |
| Other | UNKNOWN |

Two things to note:

1. **There is no `JOB` type, only `JOB_RUN`.** A pipeline isn't modelled as a navigable entity — only its individual runs are. The expectation is that the orchestrator (Airflow, dbt, etc.) is the source of truth for pipeline structure; ODD only catches the runs.
2. **There is no `DATA_QUALITY_TEST` type.** Test results land as JOB_RUN entities with a `data_quality_test_run` payload, but the test definition itself doesn't get a dedicated entity type. The expectation is that the test framework (Great Expectations is the primary integration) owns the test catalog; ODD shows the results.

## The DataEntity envelope

| Field | Meaning |
|---|---|
| `oddrn` | Globally unique identifier |
| `name` | Display name |
| `description` | Markdown |
| `type` | One of the enum above |
| `data_source_oddrn` | Parent data source under which this entity lives |
| `owner` | Optional owner OddRN |
| `tags` | Optional list |
| `metadata` | Optional list of `{schema_url, metadata}` extension blocks |

Then one or more typed payload blocks depending on type:

| Block | Used by | Carries |
|---|---|---|
| `dataset` | TABLE, VIEW, FILE | `field_list` (column schemas), `parent_oddrn`, `rows_number`, statistics |
| `data_transformer` | Output entities (TABLE / FILE produced by a job) | `inputs[]`, `outputs[]`, `source_code_url` |
| `data_transformer_run` | JOB_RUN | `transformer_oddrn`, `start_time`, `end_time`, `status`, `status_reason` |
| `data_quality_test_run` | JOB_RUN | `data_quality_test_oddrn`, `start_time`, `end_time`, `status`, `status_reason` |
| `data_consumer` | DASHBOARD, ML_MODEL | `inputs[]` |
| `data_input` | Source raw inputs | `outputs[]` |
| `ml_model` | ML_MODEL | `model_family`, `training_jobs`, `target_field` |

Lineage is implicit in these blocks. A TABLE with a `data_transformer.inputs` of `[upstream_oddrn]` declares an edge. There's no separate lineage endpoint.

## Persistence

| Store | Role |
|---|---|
| Postgres | Source of truth + search index. Entities, tags, owners, terms, ingestion logs all in normal SQL tables. Full-text search via `tsvector`. |
| | (Nothing else.) |

The platform doesn't run Kafka, doesn't run Elasticsearch, doesn't run a graph database. Everything is normalised SQL. Lineage walks are recursive CTEs against the entity table. Search is `tsvector @@ to_tsquery(...)`.

This is the single biggest architectural difference from OMD (which adds Elasticsearch) or DataHub (which adds Kafka + Elasticsearch + Neo4j). The trade-off is performance scaling — full-text Postgres search is fine for tens of thousands of entities, less fine for millions.

## The ingestion API

The headline endpoint:

| Endpoint | Purpose |
|---|---|
| `POST /ingestion/entities` | Push one or more DataEntities. Body: `{data_source_oddrn, items: [...]}` |
| `POST /api/datasources` | Register a DataSource (must exist before entities under it can be ingested) |
| `GET /api/datasources` | List sources |
| `POST /api/datasources/{id}/tokens` | Generate a token for a data source |
| `GET /api/dataentities` | List entities, with filters |
| `GET /api/dataentities/{id}/lineage` | Walk the lineage graph from an entity |
| `POST /api/owners` / `tags` / `terms` | Manage governance entities |

Authentication is a token in `Authorization: Bearer <token>`. Two scopes exist: collector tokens (created in the UI under Management → Collectors, scope to manage their own data sources) and data-source tokens (created when a data source is registered, scope to push entities under that source).

## What the model omits

This is where the comparison stories get sharpest:

- **No aspects.** Entities are monolithic. Two producers cannot independently update non-overlapping pieces of the same entity without re-sending the whole envelope. Re-ingest overwrites the existing record.
- **No pipeline-as-asset.** The orchestrator is assumed external; ODD records runs, not definitions.
- **No DQ-test-as-asset.** The DQ framework is assumed external; ODD records results.
- **No event bus.** Producers push on a schedule via HTTP. There's no `MetadataChangeLog` consumers can subscribe to.
- **No environment (PROD/DEV) in the identity.** Where DataHub URNs encode environment, ODD OddRNs assume the producer disambiguates via host. Same entity name in two environments needs two different host OddRNs.
- **No native column-level lineage rendering.** The model permits column-mappings on `data_transformer` blocks, but the open-source UI renders only table-level edges.

These aren't omissions in the sense of missing features — they're the consequence of the design choice that ODD is a **spec for interchange**, not a **catalog with opinions about how producers should be structured**.

## Mental shortcut

When stuck on "how do I do X in ODD", three questions land most tasks:

1. **What's the OddRN?** (Construct it from the source system's natural identifiers.)
2. **What DataEntityType fits?** (From the closed enum; pick the closest if a perfect match doesn't exist.)
3. **Which payload block carries the relationship?** (`data_transformer` for lineage, `data_consumer` for read relationships, `dataset.field_list` for schema.)

If those three are clear, the entity body writes itself.

## Why this shape

The design bet is that **interop matters more than feature parity**. A spec that's small and stable can be implemented by anyone — collectors, alternative platforms, custom internal tools — without a vendor in the middle. The platform itself stays simple because it doesn't need to be the source of truth for every concept; it only needs to render the spec correctly.

The trade-off is that the surface is smaller. Things OMD or DataHub treat as first-class (pipelines, DQ tests as authored assets, fine-grained event-driven updates) are either out-of-scope or pushed onto producers. For organisations that want their catalog to be a polished product, that's a gap. For organisations that want their catalog to be a thin layer over their existing producers, that's the point.
