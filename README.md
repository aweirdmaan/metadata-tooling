# Metadata tooling — three catalog POCs

Three side-by-side POCs of the same Scala/Spark pipeline against three open-source data catalogs.

## Layout

| Folder | Catalog | UI |
|---|---|---|
| [`omd/`](./omd) | OpenMetadata 1.12 | http://localhost:8585 |
| [`datahub/`](./datahub) | DataHub (Acryl quickstart) | http://localhost:9002 |
| [`odd/`](./odd) | Open Data Discovery Platform | http://localhost:8090 |

Each subdirectory is a self-contained POC with its own `setup.sh`, Scala/sbt project, seed scripts, and docs.

## Quick start

```bash
./setup-all.sh                  # interactive picker
# or
cd omd     && ./setup.sh
cd datahub && ./setup.sh
cd odd     && ./setup.sh
```

Each `setup.sh` is idempotent.

### One manual step (OMD only)

OMD's seed scripts authenticate as the `ingestion-bot` service account, whose JWT is generated when the server boots and can only be retrieved from the UI. Two phases:

1. `cd omd && ./setup.sh` — brings the stack up, then pauses at the JWT prompt.
2. Open <http://localhost:8585>, login `admin@open-metadata.org` / `admin`, go to **Settings → Bots → ingestion-bot → Token**, copy the `ey…` string, paste it back at the prompt.

Re-running with `OMD_JWT="ey…" ./setup.sh` skips the prompt entirely. DataHub and ODD don't need this — their setup scripts handle auth themselves.

## Documentation

- [`omd/docs/omd-capability-brief.html`](./omd/docs/omd-capability-brief.html) — what OpenMetadata does
- [`omd/docs/omd-domain-model.html`](./omd/docs/omd-domain-model.html) — OMD entity model
- [`datahub/docs/datahub-capability-brief.html`](./datahub/docs/datahub-capability-brief.html) — what DataHub does
- [`datahub/docs/datahub-domain-model.html`](./datahub/docs/datahub-domain-model.html) — DataHub aspect model
- [`odd/docs/odd-capability-brief.html`](./odd/docs/odd-capability-brief.html) — what ODD does
- [`odd/docs/odd-domain-model.html`](./odd/docs/odd-domain-model.html) — ODD spec-first model
- [`comparison.html`](./comparison.html) — side-by-side comparison of all three

OMD's Elasticsearch and DataHub's OpenSearch both bind `:9200`. Run one catalog at a time, or remap.

## History

Each POC's history is preserved under its subdirectory, merged via `git filter-repo --to-subdirectory-filter`. Use `git log -- omd/` (or `datahub/`, `odd/`) to walk the slice-by-slice commits for one POC.

## Host ports

All three stacks coexist; host ports are non-overlapping.

| Catalog | Service | Host port |
|---|---|---|
| OMD | Server (UI + API) | 8585, 8586 |
| OMD | Postgres | 5432 |
| OMD | Elasticsearch | 9201, 9301 |
| OMD | Embedded Airflow | 8081 |
| DataHub | Frontend (UI) | 9002 |
| DataHub | GMS | 8080 |
| DataHub | MySQL | 3306 |
| DataHub | Kafka | 9092 |
| DataHub | OpenSearch | 9200 |
| ODD | Platform (UI + API) | 8090 |
| ODD | Postgres | 5532 |
