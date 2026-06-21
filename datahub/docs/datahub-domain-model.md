# DataHub — the domain model

Once the aspect model clicks, every API call, UI tab, and connector lands in a predictable place.

## The core idea

DataHub doesn't store entities as single JSON documents. An **Entity** is a URN plus a collection of independently-versioned **Aspects** — small typed fragments. A Dataset isn't a row; it's the sum of whatever aspects have been attached: `datasetProperties`, `schemaMetadata`, `ownership`, `glossaryTerms`, `globalTags`, `datasetProfile`, `upstreamLineage`, and so on.

This is the design decision that ripples through everything else. Two independent producers can update two independent aspects on the same entity without colliding. The search index updater is just another aspect consumer subscribed to the same Kafka topic. Versioning is per-aspect, not per-entity — a description change bumps `datasetProperties` v=12 → v=13 while leaving `schemaMetadata` at v=4. Schema evolution is additive: new aspects can be defined and start landing without breaking existing producers.

## The standard envelope

Every Entity carries:

| Field | Meaning |
|---|---|
| URN | `urn:li:<entityType>:(...)` — globally unique, encodes the entity's type and identity |
| Aspects | One or more typed records attached to this URN |
| Version (per aspect) | Monotonic counter; v=0 is the latest, prior versions retained for history |
| AuditStamp (per aspect) | `{time, actor}` recording who wrote this aspect when |

The URN format is verbose but deterministic:

```
urn:li:dataset:(urn:li:dataPlatform:snowflake,db.schema.table,PROD)
urn:li:dataFlow:(airflow,my_dag,PROD)
urn:li:dataJob:(urn:li:dataFlow:(airflow,my_dag,PROD),my_task)
urn:li:assertion:abc123
urn:li:corpuser:datahub
```

Platform + name + environment are encoded into the identity. Environment (`PROD`, `DEV`, `STAGING`) is first-class, not a tag.

## The entity types

Entities are defined in Pegasus schemas and the catalog grows release by release. The current canon:

| Category | Entities |
|---|---|
| Data assets | Dataset, Container, Chart, Dashboard, MLModel, MLFeature, MLModelGroup, MLFeatureTable, MLPrimaryKey |
| Pipelines | DataFlow (a flow / DAG), DataJob (a task inside a flow), DataProcessInstance (a run) |
| Schema | DataPlatform, DataPlatformInstance |
| People | CorpUser, CorpGroup, Role |
| Governance | Tag, GlossaryTerm, GlossaryNode, Domain, DataProduct, BusinessAttribute |
| Quality | Assertion, Test, Incident |
| Operational | Notebook, Query, SchemaField |

Each entity type defines which aspects it accepts. A Dataset accepts `datasetProperties`, `schemaMetadata`, `ownership`, `glossaryTerms`, `globalTags`, `upstreamLineage`, `datasetProfile`, `assertions`, `domains`, `datasetUsageStatistics`, `editableDatasetProperties`, `status`, `siblings`, and more. An Assertion accepts `assertionInfo`, `assertionRunEvent`, `ownership`, `status`.

## Aspect categories

Aspects fall into rough groups:

| Group | Examples | Notes |
|---|---|---|
| Identity / definition | `datasetProperties`, `schemaMetadata`, `dataJobInfo`, `dataFlowInfo` | The "what is this" aspects |
| Relationships | `upstreamLineage`, `dataJobInputOutput`, `containedIn`, `siblings` | Edges to other URNs |
| Governance | `ownership`, `globalTags`, `glossaryTerms`, `domains`, `dataProducts` | Cross-cutting concerns |
| Operational | `status`, `datasetProfile`, `datasetUsageStatistics`, `assertionRunEvent` | Runtime / time-series data |
| Editorial | `editableDatasetProperties`, `institutionalMemory` | UI-edited overlays that don't get clobbered by ingestion |

The split between `datasetProperties` (from ingestion) and `editableDatasetProperties` (from UI edits) is one of DataHub's quieter clever bits — it solves the "every re-ingest clobbers the description I just wrote" problem cleanly.

## Lineage as a graph

Lineage isn't an aspect attached only to datasets. It's a graph that overlays the entity tree, populated primarily by the `upstreamLineage` aspect on whichever entity is downstream. Edge structure:

| Field | What it is |
|---|---|
| `dataset` | The upstream URN (any entity type, not just Dataset) |
| `type` | `TRANSFORMED`, `COPY`, `VIEW`, etc. |
| `auditStamp` | When and who recorded this edge |
| `properties` | Optional metadata about the edge itself |

Column-level lineage lives in a separate `fineGrainedLineages` field on the same aspect: a list of `{upstreamFields, downstreamFields, transformOperation}` mappings.

Any entity type can be at either end of an edge. The graph store renders heterogeneous nodes — Tables → Dashboards, Pipelines → ML Models, Topics → Tables — in one view.

## Pipelines as DataFlow + DataJob

The pipeline model uses two entities, not one:

| Entity | Role |
|---|---|
| DataFlow | A pipeline service or DAG. URN encodes the orchestrator (airflow, spark, dagster). Holds `dataFlowInfo`, `ownership`. |
| DataJob | A task / executable within a flow. URN nests the parent DataFlow URN. Holds `dataJobInfo`, `dataJobInputOutput` (declaring upstream and downstream datasets + upstream jobs), `ownership`, `globalTags`. |
| DataProcessInstance | A single run of a DataJob (optional). Carries start/end time, status. |

`dataJobInputOutput` is what tells DataHub which datasets feed this job and which it produces, allowing the lineage view to render pipelines as nodes between data assets.

## Data quality (Assertions)

Assertions are first-class entities, not children of a test suite:

| Aspect | Purpose |
|---|---|
| `assertionInfo` | Definition: dataset URN, scope (DATASET / DATASET_COLUMN), fields, operator (`NOT_NULL`, `BETWEEN`, `EQUAL_TO`...), parameters, source (NATIVE / EXTERNAL / GREAT_EXPECTATIONS / SODA) |
| `assertionRunEvent` | Time-series of runs, each with status (COMPLETE / RUNNING / FAILURE) and result (SUCCESS / FAILURE / ERROR), plus observed values |
| `ownership` | Who owns this assertion |
| `status` | Soft-delete flag |

Native and external (GX, Soda) assertions share the same schema. The UI surfaces all of them the same way, with status badges on the dataset's lineage node and detailed run histories on the dataset's "Quality" tab.

## Governance entities

| Entity | What it represents |
|---|---|
| CorpUser, CorpGroup | People and teams; attached to anything via the `ownership` aspect |
| Tag | A label; attached via `globalTags`. Tiers are tags by convention (`urn:li:tag:Tier1`) |
| GlossaryTerm | Hierarchical business vocabulary; attached via `glossaryTerms` |
| Domain | Business grouping; attached via `domains`. Assets belong to one domain |
| DataProduct | Consumer-facing bundle of assets |
| Role / Policy | Permission grants; attached to users/groups |

## Persistence layer

| Store | Role | What it holds |
|---|---|---|
| MySQL (or Postgres) | Source of truth | One row per (URN, aspectName, version) — the entire history of every aspect on every entity |
| Kafka | Event bus | Topics like `MetadataChangeLog_v1` carrying every aspect mutation. Multiple consumers subscribe |
| Elasticsearch | Derived projection | Reindexed by a Kafka consumer on every aspect change. Powers search, type-ahead, the Insights view |
| Neo4j (or MySQL graph mode) | Lineage graph | Reindexed by a Kafka consumer when lineage aspects change. Powers the lineage walks |

The pattern is uniform: MySQL holds truth, Kafka carries change events, and every derived view is a consumer that can be rebuilt from scratch by replaying the topic. The trade-off is operational weight — Kafka and Neo4j are not optional.

## The API surface

| Endpoint | Purpose |
|---|---|
| `GET /api/graphql` | Primary read surface; ask for an entity and its aspects in one shot |
| `POST /aspects?action=ingestProposal` | Write any aspect on any entity — the universal write endpoint |
| `GET /entities/{urn}` | Restli read; entity envelope + aspects |
| `POST /openapi/v3/entity/{type}` | OpenAPI write surface (newer, friendlier than Restli) |
| `GET /openapi/v3/entity/{type}/{urn}/{aspect}` | OpenAPI read of one aspect |
| `POST /relationships?action=findRelated` | Graph queries |
| `POST /search?action=search` | Direct ES search |

The OpenAPI v3 endpoints are the easier on-ramp for scripting; the Restli endpoints are the legacy primary surface, still used by every Python SDK call under the hood.

## Why this shape

Three design decisions explain the whole platform:

1. **Aspects, not documents.** Producers and consumers decouple at the aspect boundary. A Spark job emits `upstreamLineage`; an Airflow recipe emits `dataJobInfo`; a GX run emits `assertionRunEvent`. Three independent producers writing to the same Dataset URN, never colliding.

2. **Kafka as the metadata bus.** Every aspect mutation publishes a typed event. Search, lineage, alerting, downstream integrations all subscribe. This is what makes DataHub fundamentally event-driven rather than request-driven.

3. **Versioning per aspect.** A description edit doesn't bump the schema's version. History is granular, audit logs are precise, rollbacks are surgical.

The cost is operational. Six-plus containers, Kafka and a graph store to run, MySQL alongside ES — all things that have to stay up, get backed up, and scale together. DataHub is not the lightweight option.

## Mental shortcut

When stuck on "how do I do X in DataHub", three questions land most tasks:

1. **What entity type and URN?** (`urn:li:dataset:(...)`, `urn:li:dataJob:(...)`, etc.)
2. **Which aspect carries the data?** (`ownership`? `datasetProfile`? `upstreamLineage`?)
3. **Read or write?** (GraphQL for reads; `ingestProposal` with the aspect payload for writes.)

The aspect taxonomy is the catalog of capabilities. Once it's mapped, the API and UI follow.
