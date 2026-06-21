# Three catalogs, three different bets

OpenMetadata, DataHub, and Open Data Discovery solve the same headline problem — give a data platform a single searchable surface for every asset, with lineage and quality on top — and pick three genuinely different architectures to do it. This is what each picks, and what falls out as a consequence.

---

## The headline

| | OpenMetadata | DataHub | Open Data Discovery |
|---|---|---|---|
| Treats the catalog as | A product | A platform | A protocol |
| Unit of metadata | One JSON document per entity | Independently-versioned aspects | One DataEntity envelope per OddRN |
| Identity | `service.db.schema.table` (FQN) | `urn:li:dataset:(platform,name,env)` | `//platform/host/.../path/...` (OddRN) |
| Storage | Postgres + Elasticsearch | MySQL + ES + Kafka + Neo4j | Postgres only |
| Event model | Webhooks (bolted on) | Kafka (first-class) | None — schedule-driven HTTP push |
| Primary API | REST + JSON Schema | GraphQL primary; REST + OpenAPI write | REST + ODD Spec |
| Containers to operate | ~4 | ~6 to 9 | ~2 |
| Connector library | ~80 | ~80+ | ~30 |
| Runtime Spark lineage | OpenMetadata Spark Agent | `acryl-spark-lineage` listener | Limited; usually pushed from a wrapper |
| Built-in DQ | ~25 test types, Incident workflow | Native Assertions + GX / Soda re-uses the same model | Records external runner results; doesn't author tests |
| Pipeline as a first-class entity | Yes (Pipeline) | Yes (DataFlow + DataJob) | No (only JOB_RUN) |
| Authored DQ test as a first-class entity | Yes (TestSuite + TestCase) | Yes (Assertion) | No |
| Column-level lineage | Yes, where producer supplies it | Yes, via fineGrainedLineages | Spec allows it; default UI doesn't render |

---

## Why "product vs platform vs protocol" matters

The three labels aren't marketing. They describe what each tool will fight for if everything else has to bend.

**OpenMetadata** fights for a coherent user experience. One team owns the connector framework, the API, the UI, the agent, the embedded Airflow. New asset types ship with full UI support. The trade-off: heavier opinions about how producers should look. If a producer doesn't fit OMD's expected shape, the friction is real (the Spark agent's `locationPath` lookup, for example, expects a particular file-path convention; deviate and lineage stays orphaned).

**DataHub** fights for decoupling. Aspects let independent producers update non-overlapping pieces of the same entity without colliding. Kafka means consumers (search, lineage, alerting, external integrations) all see the same change stream. The trade-off: operational weight. Kafka and Neo4j aren't optional, and the quickstart is several env vars and an init container away from working.

**ODD** fights for interop. The product is the spec, not the platform. Anyone who emits ODD-shaped JSON gets ingested; anyone who reads ODD-shaped JSON can consume. The platform stays small because it doesn't have to be the source of truth for every concept. The trade-off: smaller feature surface. Pipelines and DQ tests aren't first-class entities; the model assumes external systems own those concepts.

---

## How they shape Spark lineage

This is one of the places the three diverge most clearly, because it's the most common "runtime metadata" producer.

**OpenMetadata** ships an opinionated Spark Agent — a `SparkListener` that posts events directly to OMD's `/api/v1/lineage` endpoint. It auto-creates pipeline entities in OMD as a side effect of the job running. The catch (learned the hard way during this POC): the agent looks up source / sink tables by `locationPath` field via Elasticsearch. If those tables don't have a matching path indexed, lineage events post successfully but orphan. Either pre-register the assets via a connector that populates `locationPath` correctly, or post lineage edges directly via the API.

**DataHub** ships `acryl-spark-lineage` (a Maven artifact, no separate jar download needed) which posts to GMS via the REST emitter. It uses URN-based identity (`urn:li:dataset:(urn:li:dataPlatform:file,<path>,PROD)`) so as long as the URN deterministically resolves, edges land. The Acryl listener also auto-creates `DataJob` entities in DataHub for the Spark application, including input/output declarations.

**ODD** doesn't have a Spark integration with the same scope. There's an `odd-collector-spark` project but it's narrower than the OMD or DataHub agents — closer to capturing job catalog than fine-grained read/write lineage. The pragmatic path for ODD with Spark today is to POST lineage edges directly from a wrapper script, treating ODD's ingestion API as the lowest common denominator.

For Spark-heavy environments, OMD and DataHub are clearly ahead. ODD's model can represent the same edges; it just lacks the off-the-shelf producer.

---

## How they shape data quality

**OpenMetadata** has the most opinionated DQ surface. About 25 built-in test types are baked into the platform, results land as time-series, failures auto-create Incidents with a resolve workflow, and the embedded Airflow runs scheduled test suites. The UI surfaces it as a "Data Quality" tab on every table page with DQ status badges that overlay onto the lineage graph nodes. Tests live in the catalog (UI-editable) or in YAML (`metadata test`).

**DataHub** treats Assertions as first-class entities. The schema accommodates native DataHub assertions, Great Expectations runs, and Soda runs through one common shape. The platform's role is the catalog and the alerting surface; running the assertions is delegated to the producer. A native assertion is operationally similar to a Great Expectations check — both end up posted as `assertionInfo` + `assertionRunEvent` aspects via the same API.

**ODD** has the thinnest DQ story. There's no `DATA_QUALITY_TEST` entity type. Tests come in as Great Expectations integration results, which post `JOB_RUN` entities with `data_quality_test_run` payloads. The platform renders them but doesn't author them. For teams whose DQ already lives in Great Expectations or dbt tests, ODD is fine. For teams expecting to define checks inside the catalog UI, it's a real gap.

---

## How they shape governance

**OpenMetadata**: owners, tiers, domains, data products, and a hierarchical glossary, all attached to entities as cross-cutting concerns. The "Data Insights" view aggregates these into governance KPIs (ownership coverage, tier coverage, description coverage, DQ pass-rate over time) and renders a dashboard out of the box. The numbers stay at zero until curation happens — which is the design.

**DataHub**: a richer governance model with multiple owner types (DATAOWNER, TECHNICAL_OWNER, BUSINESS_OWNER, STEWARD), domains, data products, glossary terms, and BusinessAttributes. Tiers are conventionally encoded as tags (`urn:li:tag:Tier1`). The governance KPIs surface through a "Analytics" / "Stewardship" view, and via the GraphQL API for custom dashboards.

**ODD**: owners and tags exist; tiers and domains don't have first-class equivalents (tiering is a tag-naming convention). The governance scoreboard is thinner. Terms exist for business vocabulary, similar to OMD's glossary.

---

## How they shape evolution

Schema evolution under the three models tells you a lot about the architecture:

**OpenMetadata** ships breaking changes by versioning entities in-place. A new asset type means a new entity class, with full UI support added in the same release. Backwards compatibility on the API is reasonable but not absolute; major version upgrades sometimes require connector reconfiguration.

**DataHub** evolves additively. Adding a new aspect to an existing entity doesn't break existing producers — they just continue to write the aspects they know about. New entity types ship as new URN schemas. The Pegasus schema language is the lingua franca; adding fields is a non-breaking change by default.

**ODD** evolves via the spec. Schema versions are published openly and producers / consumers update at their own pace. The spec is small enough that breaking changes are rare; when they happen, the migration is mechanical.

---

## What this POC actually showed

The three were stood up locally side-by-side with the same source data (a small Scala/Spark project producing parquet files through two jobs). The catalog content ended up looking like this:

| | OMD | DataHub | ODD |
|---|---|---|---|
| Data assets in the catalog | 4 tables | 4 datasets | 4 data entities |
| Pipelines as visible entities | 2 Pipelines under `spark-poc` Pipeline Service | 2 DataJobs under a `spark-poc` DataFlow | None (no `JOB` type in the enum) |
| Lineage edges | 3 table-to-table, with column lineage on simple aggregations | 2 dataset-to-dataset, with column lineage | 3 table-to-table (table-level only; column lineage not rendered) |
| DQ tests visible | 2 (one green, one red, with an Incident on failure) | 2 Assertions (one SUCCESS, one FAILURE assertionRunEvents) | Not authored as first-class entities |
| Owners / tiers / descriptions | All populated | All populated (4 tiers, ownership, domain, profiles) | Datasets and lineage; owners/tags need separate management API calls |
| Operational complexity to land all of the above | Moderate — fixed the agent's locationPath lookup with a manual lineage post and the DB migration init order | Moderate — fixed token signing keys, the aspect.value-as-string serialisation, and a Restli em-dash rejection | Lowest — fixed the data source registration ordering and worked within the closed type enum |
| Containers up at the end | 4 | 7 | 2 |

The ODD result isn't poorer wiring; it's the model. ODD doesn't model authored pipelines or authored DQ tests as catalog assets. That's the architectural bet.

---

## Picking between them

**If the platform is Java/Spark, self-hosting is acceptable, and one team will own the catalog as a product**: OpenMetadata. The agent is the strongest in this lane, the UI is polished, the DQ surface is the most opinionated, the embedded Airflow makes setup cohesive.

**If many independent producers will write metadata to the same catalog, event-driven semantics matter, and operating Kafka is fine**: DataHub. Aspects + Kafka are exactly the right shape; the operational weight is the price.

**If interop with a metadata standard is the priority, or the ops budget is small and the catalog UX is secondary**: Open Data Discovery. The spec is the product; the platform is the easy reference consumer.

**If self-hosting is the binding constraint and budget exists**: commercial — Atlan, Collibra, Alation. Polished UX, hosted, much higher cost, curation labour often subsidised by the vendor's own data engineers.

The choice usually hinges on three questions:

1. **How many independent metadata producers will write to this catalog?** Many → DataHub. Few → OMD or ODD.
2. **How important is the in-catalog DQ authoring story?** Very → OMD. Externally-owned DQ → DataHub or ODD.
3. **How much ops appetite is there?** A lot → DataHub. A little → ODD. Middle → OMD.

The one constant across all three: **the catalog only stays useful if curation is part of someone's routine.** The technical install is the easy part. Owners, descriptions, tiers, tests don't keep themselves current. Whichever tool gets picked, the operational story for the platform team is the same — and it's the long pole, not the deployment.
