# Team Rocket — project wiring

POC: OpenMetadata local docker + sample Spark jobs (based on upstream profile-based pattern) with lineage and DQ checks. Goal is a working demo to elaborate OMD from lineage/DQ/dashboard perspectives. Accuracy and production-grade structure are explicitly NOT goals.

## Task tracker

- **Tool:** beads (`bd`), local-only — no remote, no git remote
- **Workspace:** `pocs/omd/.beads` (issue prefix `omd-`)
- **CLI:** `bd ready` (find work), `bd show <id>`, `bd update <id> --claim`, `bd close <id>`
- **Story hierarchy:** beads supports dependencies via `--blocks` / `--blocked-by`. Use a top-level umbrella issue with sub-issues hanging off it. Tag the umbrella with `epic`, goals with `goal`, implementations with `impl`, discovery with `eda`.
- **Persistent memory:** `bd remember "insight"` and `bd memories <keyword>` — DO NOT use `MEMORY.md` in this directory (the parent monorepo's MEMORY.md lives elsewhere and serves a different purpose).

## Source control

- **Repo:** `pocs/omd` (newly `git init`-ed, no remote yet)
- **Default branch (off-limits to agents):** `main`
- **Feature-branch pattern:** `omd-NNN-short-slug` matching the beads issue ID

## CI / gates

- **Pre-commit:** none yet — POC is greenfield
- **CI:** none — local-only
- **Local validation:** `docker compose up`, plus `sbt test` / `gradle test` once Scala jobs land
- **Toolchain pins (no-touch once added):** `.tool-versions`, `docker-compose.yml`, `build.sbt` / `build.gradle.kts`

## Codebase vocabulary

Empty — POC has no code yet. Borrow vocabulary from the parent upstream repos as appropriate:

| Word | Meaning here | Source |
|------|--------------|--------|
| profile-based | Dataset deriving a sensor's profile from sensor_readings | `a typical Scala/Spark project/profile-based-*` |
| dataset (typed) | `Dataset[CaseClass]` over raw `DataFrame` | `a typical Scala/Spark project` newer modules |
| SparkMain | Entry-point trait wrapping `args -> spark -> run` | `a typical Scala/Spark project` |

## Pattern hierarchy

- **Prefer:** the homebased dataset pattern (typed Datasets, case-class schemas, `SparkMain[CliArgs]`, `DatasetIO` helpers). See user memory entry `project_ada_homebased_dataset_pattern`.
- **Avoid mirroring:** `enrich-poi-with-geohash` (older, untyped style).
- **OMD lineage hookup:** use openmetadata-ingestion's `spark-lineage` listener (`spark.extraListeners` config) OR run the `metadata` CLI against produced datasets. Pick the simplest path that produces visible lineage edges.

## Test conventions

- Unit / component: colocate with source (`src/test/scala/...` mirroring `src/main/scala/...`)
- Integration: any test that needs the local OMD docker stack lives under `it/` and is excluded from unit runs
- Assertion style: structural equality on case-class outputs; one logical assertion per test

## Codebase exceptions to the failure-modes list

| Failure-mode entry | Why it's OK here |
|--------------------|------------------|
| Hardcoded sample data | This is a POC — synthetic CSVs / parquet checked into `sample-data/` are expected |
| Skipped error handling | POC scope; jobs can let Spark exceptions bubble |
| No retries / idempotency | Demo runs are single-shot |

## Companion files (read first)

- `<team-rocket>/skills/rally/philosophy.md`
- `<team-rocket>/skills/rally/failure-modes.md`
- `<team-rocket>/skills/rally/examples.md`
- `<team-rocket>/skills/rally/playbook.md`

## Spawn-prompt boilerplate

Every james / jessie / meowth spawn must include the four companion files above plus this file.
