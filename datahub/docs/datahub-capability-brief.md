# DataHub

A read on what DataHub is, what it does, and where it's thin.

---

## What it is

A self-hosted metadata platform built around an event-driven architecture. The mental model is closer to a Kafka-fronted metadata bus than a CRUD catalog: anything that produces metadata publishes a typed event ("this dataset got a new owner", "this pipeline finished a run"), and many consumers — the search index, the lineage graph store, the alerting engine, external integrations — subscribe and react.

Originally built at LinkedIn, now stewarded by Acryl Data. Java/Spring backend (the GMS service), React UI, and a fairly heavy stack: MySQL for entity state, Kafka for the event bus, Elasticsearch for search, Neo4j (or MySQL) for the lineage graph, plus several JVM services that consume from Kafka and update the indexes. Six to nine containers in a typical deployment.

Connectors are Python recipes (`pip install acryl-datahub`, run via `datahub ingest -c recipe.yml`) that pull metadata from external systems — Snowflake, dbt, Airflow, Tableau, BigQuery, Kafka itself, and so on.

## How the model is shaped

The thing that distinguishes DataHub from every other catalog is **aspect composition**. Where OpenMetadata stores each entity as one monolithic JSON document, DataHub stores it as a collection of independently-versioned **aspects** — small typed fragments.

A `Dataset` entity in DataHub isn't a single record. It's an URN plus whatever aspects have been attached: `datasetProperties`, `schemaMetadata`, `ownership`, `glossaryTerms`, `globalTags`, `datasetProfile`, `upstreamLineage`, and so on. Each aspect has its own version history. Two producers can update two different aspects on the same entity without ever touching each other.

The shape:

| Layer | Examples |
|---|---|
| Entity | Dataset, DataFlow, DataJob, Chart, Dashboard, MLModel, Tag, GlossaryTerm, CorpUser, CorpGroup, Domain, Container, DataProduct |
| Aspect | ownership, datasetProperties, schemaMetadata, upstreamLineage, datasetProfile, globalTags, assertions, status, datasetUsageStatistics |
| Identity | `urn:li:dataset:(urn:li:dataPlatform:snowflake,fct_users,PROD)` — platform + name + environment encoded into one string |
| Storage | MySQL (entity-aspect rows), Elasticsearch (search), Kafka (event log), Neo4j or MySQL (graph) |

Lineage is one aspect among many — `upstreamLineage` lists the URN of upstream entities, with optional column-level mappings and pipeline references. It lives in the graph store as a separate edge table.

## What it does

### Search and discovery

Faceted search backed by Elasticsearch. Type-ahead, filters by domain / tag / glossary term / owner. Each entity has a canonical page composed dynamically from whatever aspects exist on it. Glossary terms work as searchable facets and can be applied to columns or whole datasets.

The GraphQL API at `/api/graphql` is the primary read surface — query an entity and ask for exactly the aspects you need. REST endpoints under `/aspects` and `/openapi` work for writes.

### Lineage

Graph-shaped, table-level and column-level. Edges are produced three ways:

- **Spark Lineage agent** — Acryl publishes `acryl-spark-lineage` as a Maven dependency. Drop it on the Spark classpath, set `spark.extraListeners=datahub.spark.DatahubSparkListener`, and Spark jobs post lineage events to GMS as they run.
- **Recipe-based ingestion** — connectors for dbt, Airflow, Looker, etc. parse pipeline definitions and post `upstreamLineage` aspects.
- **API** — `POST /aspects?action=ingestProposal` for direct edge creation.

The lineage view in the UI renders heterogeneous nodes: tables, dashboards, pipelines (DataFlow / DataJob), ML models can all appear in the same graph. Each edge can carry column-level mappings and a pipeline reference.

### Pipeline model

Two entity types: **DataFlow** (a pipeline service / parent group — e.g. "spark-poc") and **DataJob** (a single executable inside a flow — e.g. "build_sensor_profiles"). DataJobs declare their input/output datasets via `dataJobInputOutput`. This is what lets DataHub's lineage view show pipelines as nodes alongside data assets.

### Data quality (Assertions)

Assertions in DataHub are first-class entities, not children of a parent test suite. Two aspects matter:

- `assertionInfo` — the definition (which dataset, which column, what operator like `NOT_NULL` or `BETWEEN` with parameters)
- `assertionRunEvent` — one row per execution, with status (`SUCCESS` / `FAILURE`) and observed values

The DataHub UI surfaces assertion runs on the dataset page and renders status badges on lineage nodes. Native DataHub assertions are deterministic and threshold-based, like OMD's. The same `assertion` entity model is also how Great Expectations and Soda integrations land their results — they reuse the schema, so a GX-defined check and a native check look identical in the UI.

### Governance

- **Ownership** as an aspect, with multiple owner types (DATAOWNER, TECHNICAL_OWNER, BUSINESS_OWNER, STEWARD).
- **GlobalTags** for tier classifications (Tier1..Tier4 via `urn:li:tag:Tier1` etc.) and arbitrary tagging.
- **Glossary** with hierarchical terms and synonyms; terms can be attached to columns.
- **Domains** for business grouping; assets belong to a domain via the `domains` aspect.
- **DataProducts** for consumer-facing bundles of assets.

### Profiling

`datasetProfile` aspect carries time-series stats — row count, column count, size in bytes, plus per-column `fieldProfiles` with null counts, unique counts, min/max, mean, sample values. Profiles get produced either by recipe-based profilers (run on a schedule) or pushed directly via the API.

### Alerting and webhooks

Because everything flows through Kafka, alerting is a first-class consumer pattern. Subscriptions filter events ("any Assertion with status=FAILURE on a Tier1 Dataset") and fan out to Slack, MS Teams, PagerDuty, email, or arbitrary webhooks. The same mechanism is how the search-index updater stays current — there's no distinction between "internal sync" and "external integration" at the platform layer.

### Auth and access

OIDC (Okta, Azure AD, Google, Auth0), JWT, and the default username/password setup. The quickstart ships with token-based auth disabled and `datahub/datahub` as the only login. A roles + policies framework controls who can edit what aspect on which entity type, with support for fine-grained policies like "Marketing team can edit `ownership` on assets where domain=Marketing".

### Connectors

Around 80 source connectors covering data warehouses (Snowflake, BigQuery, Redshift, Databricks), dashboards (Tableau, Power BI, Looker, Superset), pipelines (Airflow, dbt, Prefect, Dagster), ML (MLflow, SageMaker, Feast), and DQ producers (Great Expectations, Soda). Each is a Python module with a YAML recipe; runs ad-hoc, on a UI-managed schedule, or inside a user's Airflow.

## What it doesn't do

- **No catalog without operating Kafka.** The event bus is the core architectural commitment. A standalone "just the UI" deployment doesn't exist.
- **Heavier ops** than OMD or ODD. Six-plus containers, multiple JVM services, MySQL + Kafka + ES + Neo4j. Acryl Data sells a hosted version, suggesting most teams don't want to operate this themselves.
- **Anomaly detection is not built in.** Assertions are deterministic; statistical anomalies need Great Expectations, Monte Carlo, or a custom producer.
- **In-app BI / chart builder** doesn't exist. External BI tools register as Dashboard Services and get catalogued.
- **The quickstart isn't production-ready.** It runs everything on one node with no auth and default secrets. Real deployments need significant config.

## What surprised in this POC

Real notes from running it end-to-end:

- **Quickstart env vars aren't filled in by default.** `DATAHUB_TOKEN_SERVICE_SIGNING_KEY` and `DATAHUB_TOKEN_SERVICE_SALT` come up blank, the `system-update-quickstart` init container crash-loops, and the rest of the stack waits forever. The CLI usually sets these when it generates the compose; if running compose directly, write a `.env` first.
- **Token auth is disabled by default**, but every UI surface implies it's available. Generating a token from Settings will show "Token based authentication is currently disabled". GMS happily accepts unauthenticated writes in quickstart mode, which is fine for a POC and dangerous otherwise.
- **Aspect value must be a JSON-encoded string, not raw JSON.** The `ingestProposal` payload has `aspect.value` typed as a string carrying serialized JSON inside. Passing raw JSON returns a confusing 500 with a Restli internal-server-error stack trace pointing at validation.
- **The Restli validator rejects non-ASCII characters in some string fields.** Em dashes in descriptions caused a 400 with "is not a valid string". Hyphens fixed it.
- **MetadataChangeProposal needs `changeType`.** Setting it to `UPSERT` (or `CREATE`, `UPDATE`, `DELETE`) is required on every proposal; omitting it returns a misleading 500.
- **Pipelines are DataFlow + DataJob, not a single entity.** A pipeline visible in the lineage view requires posting two entities and linking the DataJob to its inputs and outputs via the `dataJobInputOutput` aspect. Slightly more work than OMD's single Pipeline entity.

## Running it

The POC at `pocs/datahub`:

- `datahub docker quickstart` brings up GMS, frontend, MySQL, Kafka, OpenSearch, and the system-update init container. Frontend on http://localhost:9002 (login `datahub/datahub`), GMS on http://localhost:8080.
- `scripts/seed-datahub.sh` posts the four datasets with schemas, two lineage edges, and two assertions with results.
- `scripts/populate-metadata.sh` adds the DataFlow + two DataJobs, ownership on every entity, tier tags, the `spark-poc` domain, and `datasetProfile` stats.
- `src/main/scala/com/poc/datahub/DatahubSparkSession.scala` builds a SparkSession wired with `datahub.spark.DatahubSparkListener` and the necessary `spark.datahub.rest.*` configuration so jobs land lineage at the GMS endpoint.

End state: a stack walkable through Search → Lineage → Assertions → Domain pages in the same way as OMD.
