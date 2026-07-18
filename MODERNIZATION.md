# HELK Modernization — Findings & Recommendations

**Status:** Research complete. No code changes have been made yet — this document
records the current-state inventory and the target-architecture recommendations
so implementation can start from an agreed plan rather than blind version bumps.

Repo: [Cyb3rWard0g/HELK](https://github.com/Cyb3rWard0g/HELK) — last upstream
commit 2021-05-08. Cloned shallow (`--depth 1`) into this directory for
modernization work.

**Project name:** this fork will be renamed **HELK Rebuilt**. HELK is
GPL-3.0-licensed and originally authored by Roberto Rodriguez
(`@Cyb3rWard0g`) — attribution to the original project/author should be kept
in the README/license notices, and this should be clearly presented as an
independent, unofficial fork/continuation, not an official successor. The
actual rename (image names, container/hostnames like `helk-kafka-broker` /
`helk-elasticsearch`, script variables, compose service names, etc.) is a
mechanical pass deferred to Phase 1 implementation — not done yet, since we're
still documentation-only at this stage.

---

## 1. Why modernize, not just patch

Nearly every "otrf/helk-*" image the compose files pull is a **frozen 2020/2021
Docker Hub image**, not something rebuilt from this repo's own Dockerfiles —
only `helk-jupyter` is actually built locally (`build:` in compose); every other
service (`helk-nginx`, `helk-zookeeper`, `helk-kafka-broker`, `helk-logstash`,
etc.) is pulled prebuilt, so the in-repo Dockerfiles for those services have
drifted from what's actually running. Several of those images sit on top of
`otrf/helk-base`, which is built on `phusion/baseimage:latest` — an old
init-system-in-container pattern with a floating tag. A real modernization has
to rebuild these from current, actively maintained bases, not just bump a
version string in a Dockerfile nobody is building.

---

## 2. Current-state inventory

### 2.1 Compose topology (`docker/*.yml`)

Four near-duplicate top-level compose files implement HELK's "build option
1–4" menu (chosen interactively by `helk_install.sh`). All four share one core
stack and differ only additively:

| Build | Extra services vs. core | Nginx config |
|---|---|---|
| 1 — `helk-kibana-analysis-basic.yml` | none | `basic-elk` |
| 2 — `helk-kibana-analysis-alert-basic.yml` | `helk-elastalert` | `basic-elk` |
| 3 — `helk-kibana-notebook-analysis-basic.yml` | `helk-jupyter` (built), `helk-spark-master`, `helk-spark-worker` | `basic-helk` (adds `/jupyter`) |
| 4 — `helk-kibana-notebook-analysis-alert-basic.yml` | union of 2 + 3 | `basic-helk` |

Core stack images actually pulled (not built): `docker.elastic.co/elasticsearch/elasticsearch:7.6.2`,
`otrf/helk-logstash:7.6.2.1`, `docker.elastic.co/kibana/kibana:7.6.2`,
`otrf/helk-nginx:0.3.0`, `otrf/helk-zookeeper:2.4.0`, `otrf/helk-kafka-broker:2.4.0`,
`confluentinc/ksqldb-server:latest`, `confluentinc/ksqldb-cli:latest`.

Other findings:
- All four files declare the obsolete `version: '3.5'` Compose key.
- `ADVERTISED_LISTENER: ${ADVERTISED_LISTENER}` has no default and no `.env`
  file — must be exported by the install script or Compose silently
  substitutes empty string.
- Minor drift between files: inconsistent YAML indentation for Logstash env
  vars, and Build 2/4 disagree on which files are declared under `secrets:`.
- `secrets:` blocks are Compose-file syntax but not real Docker/Swarm
  secrets here — plain files bind-mounted read-only (`elasticsearch.yml`,
  `kibana.yml`, `htpasswd.users`).

### 2.2 Install / lifecycle scripts (`docker/helk_*.sh`)

- `helk_install.sh` (v0.1.9-alpha10082020): requires root, detects
  Ubuntu/Debian/CentOS via `/etc/os-release`, explicitly rejects
  RHEL/OL/SLES, installs Docker via `get.docker.com`, and pins
  **docker-compose v1.27.4** (a comment explains this was to dodge a glibc
  issue in 1.28 — that binary/release line is long EOL now). Interactive
  prompts for Kibana password (default `hunting`), host IP, and build choice
  1–4, each with a timeout-then-default. Reads
  `../.git/refs/heads/master` directly to log the build's git ref — fragile,
  and breaks on a shallow clone (like this one).
- `helk_update.sh`: adds a remote, and if the local repo is behind,
  runs `git checkout master && git clean -d -fx . && git pull` — **this
  silently deletes untracked local files** as part of a routine "update."
  Also prompts for an Elasticsearch "trial" password defaulting to
  `elasticpassword`.
- `helk_remove_containers.sh`: tears down via
  `docker-compose -f $INSTALL_FILE down --rmi all -v`, then force-removes any
  image matching a broad grep pattern.
- `helk_setup_firewall.sh`: CentOS/firewalld-only, copies a **relative path**
  `../configs/firewalld/helk.xml`, assumes cwd is `docker/`.
- `helk_docker_install.sh`: a separate, inconsistent utility that installs
  the *latest* docker-compose (unlike `helk_install.sh`'s explicit 1.27.4 pin).

### 2.3 Nginx (`docker/helk-nginx/`)

- Local `Dockerfile` (`FROM nginx:1.17.9`) exists but is **unused** — compose
  pulls `otrf/helk-nginx:0.3.0` instead. Drift risk between the two.
- `nginx-entrypoint.sh` regenerates a **self-signed TLS cert from scratch on
  every container start** (not persisted in a volume) and blocks until
  Elasticsearch answers before starting nginx.
- Basic auth (`htpasswd.users`) gates `location /` (Kibana) but **not**
  `/jupyter` (that path relies solely on Jupyter's own token).
- `docker/helk-nginx/htpasswd.users` **ships a live htpasswd hash checked
  into git** for user `helk`, consistent with the scripts' default password
  `hunting`.

### 2.4 Elasticsearch / Kibana / Logstash

- All three pinned to **7.6.2**.
- `elasticsearch.yml` sets `discovery.type: single-node` (still valid) **and**
  the stale `discovery.zen.minimum_master_nodes: 1` — a legacy zen2 setting
  that is an *unknown, startup-fatal* setting on Elasticsearch 8+.
  `xpack.security.enabled: false` is set via compose env vars, not this file.
- Kibana saved objects (~85 NDJSON files: 7 dashboards, 17 index-patterns, 1
  map, 12 searches, ~48 visualizations) are tagged for the **7.6.2**
  saved-objects format (`objects/config/7_6_2.ndjson`).
- Logstash ships three offline "prepare-offline-pack" plugin zips totaling
  **~156MB**, built against Logstash 7.6.2, bundling plugin versions that are
  mostly part of Logstash's default bundle anyway (beats input, ES output,
  geoip filter, Kafka integration). Two plugins are genuinely non-default:
  `logstash-codec-cef` and `logstash-codec-netflow`.
- Logstash pipeline: 62 numbered `.conf` files (Kafka/beats/syslog inputs →
  ECS/OSSEM normalization → ATT&CK enrichment via a 21MB MITRE CSV →
  per-event-type ES outputs), plus a secondary `mordor` pipeline for Mordor
  dataset replay.

### 2.5 Kafka / Zookeeper / ksqlDB

- `docker/helk-kafka-base` (`FROM otrf/helk-base:0.0.4` →
  `phusion/baseimage:latest`) pins `KAFKA_VERSION=2.4.1`, downloads the
  tarball from an old Apache mirror URL that is very likely dead now.
- **Zookeeper is a hard dependency in three places**: `server.properties`
  (`zookeeper.connect=helk-zookeeper:2181`), `kafka-create-topics.sh` (uses
  the `--zookeeper` flag, **removed in Kafka 3.0**), and
  `kafka-entrypoint.sh` (`ZOOKEEPER_NAME` plumbing). No KRaft references
  exist anywhere in the repo.
- Topics created at startup: `winlogbeat`, `winevent`, `SYSMON_JOIN`,
  `filebeat`, `zeek` (replication factor 1, single partition).
- `docker/helk-ksql/` contains only a `.commands` script (KSQL streams/tables
  joining Sysmon process-create + network-connect events) — no Dockerfile.
  ksqlDB itself is pulled as `confluentinc/ksqldb-server:latest` /
  `ksqldb-cli:latest` — **floating tags on an image whose newest actual
  version tag (`0.29.0`) is ~3 years old.**

### 2.6 Spark / Jupyter / GraphFrames

- `docker/helk-spark-base`: `SPARK_VERSION=2.4.5`, `APACHE_HADOOP_VERSION=2.7`,
  no Scala version stated anywhere in-repo.
- **GraphFrames has zero version pin anywhere in this repo.** It's entirely
  baked into the external `cyb3rward0g/jupyter-hunter:0.0.9` base image,
  which is unmaintained and not vendored here.
- `docker/helk-jupyter/Dockerfile`'s `CMD` references
  `/opt/jupyter/scripts/jupyter-cmd.sh`, which **does not exist in this
  repo** — it only exists inside that external, unmaintained base image. We
  cannot see its source; it must be reverse-engineered or replaced outright.
- No `requirements.txt`/dependency manifest anywhere pins pyspark/graphframes/py4j.
- Notebooks: `notebooks/demos/` (3), `notebooks/sigma/` (**378**, one per
  Sigma rule), `notebooks/tutorials/` (7, including `06-*` which is
  specifically PySpark+GraphFrames+Sysmon). All written against ~2020-era
  GraphFrames APIs.

### 2.7 ElastAlert

- `docker/helk-elastalert` (`FROM otrf/helk-base:latest`) pins **Python 3.6**
  (EOL Dec 2021), duplicates a package line, and installs `enum34` (a
  Python-2-era backport, unneeded).
- Hard-pins `elasticsearch==7.0.0` as an explicit workaround for a known
  Yelp/elastalert bug (`Yelp/elastalert#2725`).
- `git clone https://github.com/Yelp/elastalert.git` — unpinned branch, and
  Yelp's original project is unmaintained.
- `git clone -b helk_neu5ron_updates https://github.com/Cyb3rWard0g/sigma.git`
  — **this repo no longer exists on GitHub (404)** — both at Docker build
  time and re-fetched live at container runtime by `pull-sigma.sh`.
- `pull-sigma.sh` runs the legacy `sigmac` tool twice per Sigma rule file,
  with manual workarounds for two known old sigmac bugs (`Neo23x0/sigma`
  issues #205, #209).
- 23 curated `helk_*` Elastalert rules are checked into `rules/` directly
  (separate from the ones generated live from the Sigma fork).

---

## 3. Target architecture & version decisions

Researched against current (mid-2026) sources; see citations inline.

| Area | Decision | Confidence |
|---|---|---|
| Elasticsearch/Kibana/Logstash | **9.4.x**, built from this repo's own Dockerfiles instead of pulled `otrf/helk-*` images | High |
| ES security model | Adopt native security auto-configuration (free under Basic license, on by default in 8+) instead of `xpack.security.enabled: false` | High |
| `elasticsearch.yml` | Remove `discovery.zen.minimum_master_nodes` (fatal unknown setting on 8+); keep `discovery.type: single-node` | High |
| Nginx | Rebuild from `nginx:1.30-alpine`; **wire the compose file's `build:` to the local Dockerfile** (fixes current drift); keep as TLS-terminating single entrypoint for Kibana **and** Jupyter; drop htpasswd for the Kibana path; persist the cert instead of regenerating it every start | High |
| Jupyter path auth | Open decision — see §4 | — |
| Kibana saved objects | Direct 7.6.2 → 9.x import is blocked by Kibana's version-compatibility rule (only same-major/next-major imports are accepted). Recommended: selectively rebuild the actively-used dashboards natively in Lens against 9.x data views, rather than staging three sequential Kibana migrations (7.17 → 8.19 → 9.4) for ~85 objects of unknown current value | Medium (depends on which objects are still wanted) |
| Logstash offline plugin packs | Drop entirely (~156MB). Most bundled plugins are already default; add explicit `logstash-plugin install logstash-codec-cef logstash-codec-netflow` for the two that aren't | High |
| Kafka | **`apache/kafka:4.3.1`** (official ASF image), single-node **KRaft combined mode** (`process.roles=broker,controller`), no Zookeeper. Delete `docker/helk-kafka-base` and its `phusion/baseimage` lineage entirely | High |
| Kafka topic creation | `kafka-create-topics.sh`: replace `--zookeeper helk-zookeeper:2181` with `--bootstrap-server helk-kafka-broker:9092` for all 5 topics; drop `ZOOKEEPER_NAME` plumbing | High |
| Zookeeper | Delete `docker/helk-zookeeper/` and its compose service entirely — nothing else in the stack talks to it directly | High |
| ksqlDB | Pin `confluentinc/ksqldb-server:0.29.0` / `ksqldb-cli:0.29.0` explicitly (no more `:latest`); demote to optional/legacy, not load-bearing. Longer-term replacement candidate for the Sysmon-join logic: Kafka Streams or Flink SQL (not part of this cutover) | Medium (image itself is stale/abandoned even if protocol-compatible) |
| Spark | **4.1.2**, Scala 2.13 (revised from this document's original 3.5.8/Scala 2.12 recommendation — by Phase 3 implementation time, `quay.io/jupyter/pyspark-notebook`'s newest published tag had moved to `spark-4.1.2` and Spark 3.5.x tags were no longer offered; re-verified live against Quay's tag API rather than carried forward from the original research pass) | High |
| GraphFrames | `io.graphframes:graphframes-spark4_2.13:0.12.1` (core) + `io.graphframes:graphframes-graphx-spark4_2.13:0.12.1` (its one runtime dependency — graphframes.io's install docs call out both jars as required for offline/Docker installs, not just the core artifact) + `graphframes-py==0.12.1` (Python side) — re-verified against Maven Central/PyPI at Phase 3 implementation time; still version 0.12.1, just the Spark-4/Scala-2.13-targeted artifact instead of the Spark-3/Scala-2.12 one this document originally named | High |
| Jupyter base image | Rebuild from `quay.io/jupyter/pyspark-notebook:spark-4.1.2` (Docker Hub `jupyter/pyspark-notebook` is no longer updated; the project moved to `quay.io/jupyter/*`); add the two GraphFrames jars + `graphframes-py` on top; use docker-stacks' documented `start-notebook.py` (via `before-notebook.d/` hooks for the Postgres/Hive-metastore bootstrap) instead of the vanished `jupyter-cmd.sh` | High |
| Spark standalone cluster (master/worker) | Built from the *same* `quay.io/jupyter/pyspark-notebook:spark-4.1.2` tag as the Jupyter driver, not a separate generic Spark image — PySpark requires the driver and executors to run matching Python major.minor versions, and reusing one image tag guarantees that trivially instead of hand-pinning a matching Python build across two image families (the old design's approach: a hand-installed Miniconda `python=3.7.5` in `helk-spark-worker` to match the mystery `jupyter-hunter` base's Python) | High |
| ElastAlert | Migrate to **ElastAlert2** (`jertel/elastalert2`, latest `2.30.0`), official Docker image. Note: ElastAlert2 still pins `elasticsearch==7.10.1` client-side but officially supports pointing that client at ES8/ES9 *clusters* — a deliberate, working choice, not the same kind of hack as the original `elasticsearch==7.0.0` pin | High |
| Sigma tooling | Replace `sigmac` (now archived upstream, explicitly deprecated for new projects) + the dead `Cyb3rWard0g/sigma` fork with **`sigma-cli` + `pySigma-backend-elasticsearch`** (Lucene query-string backend), sourcing rules from mainline `SigmaHQ/sigma`. No dedicated ElastAlert backend exists — wrap generated Lucene query strings into ElastAlert2 `query_string` rule YAML, same shape as the old sigmac "es-qs" backend | High |
| Compose structure | Consolidate the 4 near-duplicate YAML files into one `compose.yaml` using Compose **profiles** (`alert`, `notebook`) instead of copy-pasted files; drop the obsolete `version:` key | High |

### Sources consulted
- Elastic: [Support Matrix](https://www.elastic.co/support/matrix), [Minimal security setup](https://www.elastic.co/docs/deploy-manage/security/set-up-minimal-security), [Kibana saved-objects export docs](https://www.elastic.co/docs/extend/kibana/saved-objects/export)
- [elastic/elasticsearch#81260](https://github.com/elastic/elasticsearch/issues/81260) (zen discovery removal), [elastic/kibana#118394](https://github.com/elastic/kibana/issues/118394) (saved-object import version rule)
- Apache Kafka: [4.0.0 release announcement](https://kafka.apache.org/blog/2025/03/18/apache-kafka-4.0.0-release-announcement/), [4.0 upgrade guide](https://kafka.apache.org/40/getting-started/upgrade/), [docker/examples/README.md](https://github.com/apache/kafka/blob/trunk/docker/examples/README.md), [apache/kafka Docker Hub](https://hub.docker.com/r/apache/kafka)
- [confluentinc/ksqldb-server Docker Hub tags](https://hub.docker.com/r/confluentinc/ksqldb-server/tags), [Confluent Platform interoperability matrix](https://docs.confluent.io/platform/current/installation/versions-interoperability.html)
- GraphFrames: Maven Central `io.graphframes` metadata, PyPI `graphframes-py`, [graphframes.io](https://graphframes.io) test matrix
- Jupyter Docker Stacks: `quay.io/jupyter/pyspark-notebook` tags, [jupyter/docker-stacks](https://github.com/jupyter/docker-stacks)
- [jertel/elastalert2](https://github.com/jertel/elastalert2) releases and Docker images
- [SigmaHQ/legacy-sigmatools](https://github.com/SigmaHQ/legacy-sigmatools) (archived), [SigmaHQ/sigma-cli](https://github.com/SigmaHQ/sigma-cli), [SigmaHQ/pySigma-backend-elasticsearch](https://github.com/SigmaHQ/pySigma-backend-elasticsearch), [SigmaHQ/sigma](https://github.com/SigmaHQ/sigma)
- nginx: [Docker Hub nginx tags](https://hub.docker.com/_/nginx/tags)

---

## 4. Functionality at risk of loss — replacement candidates

These aren't just "old version → new version" swaps; each one either drops a
real capability unless something deliberately replaces it, or changes in a
way worth calling out explicitly rather than discovering later.

1. **Sysmon/network correlation (`SYSMON_JOIN`) — real capability, not just a
   stale image.** ksqlDB's actual job in this stack is joining Sysmon
   process-creation and network-connection events by `process_guid` before
   they hit Elasticsearch (see `docker/helk-ksql/sysmon-join.commands`).
   ksqlDB is being demoted to optional/legacy because its OSS image is
   abandoned (§3) — but if ksqlDB is simply dropped with nothing in its
   place, that correlation capability disappears, not just a peripheral
   service. **Recommend explicitly reimplementing the join** in Kafka
   Streams (bundled with the `apache/kafka` broker we're already keeping,
   actively maintained) or Flink SQL, rather than letting it quietly vanish
   when ksqlDB is deprioritized.

2. **Jupyter's Postgres-backed Hive metastore — must be explicitly
   re-added, not assumed.** The current `helk-jupyter` entrypoint stands up a
   local PostgreSQL instance and a `hive_metastore` database so Spark SQL
   table definitions persist across notebook restarts (`spark/hive-site.xml`,
   `scripts/jupyter-entrypoint.sh`). This setup lives entirely in the
   repo-owned entrypoint, not the old mystery base image — but
   `quay.io/jupyter/pyspark-notebook` (the new base, §3) doesn't provide it
   either, so it's easy to rebuild the image, get notebooks running, and only
   later notice table persistence silently regressed. Treat this as a
   required carry-over item in Phase 3, not an optional nice-to-have.

3. **Kibana's legacy dashboards/visualizations are at risk of not
   transferring at all.** Already noted in §3/§5 (open decision #3) — some
   of the ~85 saved objects are almost certainly built on visualization types
   (old Visualize library, TSVB, Timelion) that don't survive a 3-major
   Kibana version jump cleanly. Flagging again here because it's a genuine
   "content that may not come back" item, not just a migration-mechanics
   question — worth an explicit inventory of which of the 85 are still
   valued before deciding how much Lens-rebuild effort to spend.

4. **Sigma rule coverage — likely a net gain, but needs re-validation, not
   a straight swap.** The old pipeline's Elastalert rules were generated
   from a personal Sigma fork (`Cyb3rWard0g/sigma`, branch
   `helk_neu5ron_updates`) that no longer exists on GitHub. Replacing it with
   mainline `SigmaHQ/sigma` (3000+ actively maintained rules) is likely a
   net increase in detection coverage, not a loss — but HELK's custom
   OSSEM-to-index-pattern field mapping (`sigmac/sigmac-config.yml`) was
   written against the old `sigmac` tool's config format and will need
   re-validating against `pySigma-backend-elasticsearch`'s config format
   before assuming the extra rules actually route to the right indices.

## 5. Open decisions

1. **Jupyter path auth — resolved 2026-07-17.** Rely solely on Jupyter's
   built-in token auth (`JUPYTER_TOKEN` in `.env`), consistent with dropping
   htpasswd from the Kibana path in Phase 1 and matching the original repo's
   behavior for the notebook build variant. No separate htpasswd gate was
   added for `/jupyter`.
2. **Notebook verification depth — resolved 2026-07-17.** Spot-check: modernize
   the image, run the GraphFrames tutorial notebook plus a representative
   sample of the 378 Sigma-derived notebooks, and log systematic API breaks
   without hand-fixing all 378 individually. User explicitly asked that what
   a full fix pass would require be documented for later — see the Phase 3
   entry in §6 for the spot-check findings and that follow-up scope.
3. **Kibana saved objects.** Confirm whether the ~85 existing dashboards/
   visualizations are still wanted before investing in either the staged
   7.17→8.19→9.4 migration or selective Lens rebuilds — some may be stale
   2021-era demo content not worth carrying forward at all.
4. **How far to take the install/lifecycle scripts — resolved 2026-07-17.**
   Drop bare-metal/VM Linux provisioning entirely (root check, apt/yum,
   systemd, sysctl tuning, firewalld, installing Docker itself) rather than
   porting it to Compose v2. `helk_install.sh` / `helk_update.sh` /
   `helk_remove_containers.sh` are now thin wrappers assuming Docker +
   Compose v2 are already present; `helk_docker_install.sh` and
   `helk_setup_firewall.sh` were deleted. See the Phase 4 entry in §6 for
   the full reasoning and the two named bugs (`git clean -d -fx`, the
   hardcoded `master`-branch git-ref read) fixed along the way.

Decision #3 remains unresolved and does not gate any phase in this plan —
it only affects future Kibana-content work.

---

## 6. Proposed phased sequencing

Each phase ends with an actual `docker compose up` boot test on the local
Docker Desktop (confirmed available: Docker Desktop 4.82, Compose v5.3,
WSL2 backend).

- **Phase 0 — done.** Removed the committed htpasswd credential (`docker/.gitignore`
  now excludes it; generated at deploy time), removed the fatal stale
  `discovery.zen.minimum_master_nodes` setting from `elasticsearch.yml`.
- **Phase 1 — done.** Elasticsearch 9.4.3 + Kibana 9.4.3 + Logstash 9.4.3 +
  Kafka 4.3.1 (single-node KRaft) + Nginx (nginx:1.30-alpine, TLS-only, cert
  persisted in a volume), all built from local Dockerfiles, consolidated into
  one `docker/compose.yaml` (no `version:` key; the four old near-duplicate
  `helk-kibana-*.yml` files are deleted). Verified with a clean `docker compose
  down -v && docker compose up -d --build`: all services report healthy,
  Nginx→Kibana HTTPS proxy returns Kibana's redirect, all 5 Kafka topics exist,
  Logstash's main and mordor pipelines run with no errors. Zookeeper and the
  `phusion/baseimage`-based Kafka base are deleted entirely.
  - Along the way, found and fixed a real incompatibility beyond the original
    scope: HELK's legacy `_template` index templates for `logs-*` collided with
    Elastic's built-in reserved `logs-*-*` data-stream templates on 9.x.
    Converted ~22 of them into composable component templates + a
    priority-layered set of index templates (see
    `docker/helk-logstash/scripts/convert_templates.py` and
    `generate_index_templates.py`), verified empirically to still produce
    regular (non-data-stream) indices with HELK's original field-type mappings
    intact.
  - Confirmed deviation: ES runs with `xpack.security.enabled=true` but
    `xpack.security.http.ssl.enabled=false` / `transport.ssl.enabled=false` —
    auth is on, but TLS is terminated only at the Nginx edge, not between
    containers on the internal `helk` network. The doc's original "adopt
    native security auto-configuration" framing implied inter-node TLS too;
    user confirmed (2026-07-17) this simplification is intentional for a
    single-node internal-only deployment and should stay as-is.
- **Phase 2 — done.** ElastAlert2 2.30.0 (pip-installed, `python:3.13-slim`
  base, replacing the Yelp/elastalert git-clone build pinned to Python 3.6 and
  `elasticsearch==7.0.0`) plus a new `sigma-cli`/`pySigma-backend-elasticsearch`
  conversion pipeline, both gated behind the `alert` Compose profile
  (`docker compose --profile alert up -d --build`).
  - `helk-sigma-convert` is a new one-shot container: clones a pinned
    SigmaHQ/sigma release tag (`SIGMA_RULES_REF` in `.env`, currently
    `r2026-07-01`) at build time (no runtime git fetch), converts every rule
    under `rules/windows/` to a Lucene query via a custom pySigma processing
    pipeline, and writes one ElastAlert2 rule YAML per convertible Sigma rule
    to a volume shared with `helk-elastalert`.
  - The processing pipeline (`docker/helk-sigma-convert/pipeline/helk_ossem_pipeline.yml`)
    was generated mechanically from the legacy `sigmac-config.yml` OSSEM field
    mappings (`docker/helk-sigma-convert/scripts/generate_pipeline.py`, kept as
    a dev-time tool, not run in the container). 131 fields ported as direct
    1:1 renames; 20 EventID-conditional fields (e.g. `SubjectUserName`,
    `PrivilegeList`) were collapsed to their dominant non-identity target value
    rather than reproduced with full per-EventID fidelity — this is a
    deliberate, logged scope reduction (see the generator's own docstring and
    console output), not a silent gap. 5 fields with no safe majority mapping
    are left unmapped.
  - Logsource → HELK index routing (`docker/helk-sigma-convert/pipeline/logsource_index_map.yml`)
    is keyed by Sigma's `service` field for native Windows Event Log channels
    (security/system/application/powershell/wmi) and routes any
    `category`-based rule (process_creation, registry_event, network_connection,
    etc.) straight to the sysmon index, since every category-based rule in the
    current SigmaHQ/sigma windows/ tree is Sysmon-sourced.
  - Scope reduction vs. the original plan: the upstream Sigma repo no longer
    has a top-level `apt` rule category (reorganized since the old sigmac
    tooling was written) — only `rules/windows/` is converted. Non-Windows
    logsources and rules pySigma can't convert (e.g. one rule using a field
    reference the Lucene backend doesn't support) are logged and skipped, not
    silently dropped — see the `helk-sigma-convert` container's own stdout for
    the full skip list. Result: 2309 Sigma rules converted, 94 skipped
    (out-of-scope services HELK doesn't ingest, plus 1 genuine conversion
    error), against the pinned `r2026-07-01` tag.
  - The 23 curated `helk_*.yml` rules carried over unchanged (verified against
    ElastAlert2's rule schema; fixed one inconsistent index pattern —
    `logs-endpoint-winevent-security*` → `-security-*` — found during review).
  - Found and fixed a real conflict during boot testing: HELK's legacy
    `01-helk-elastalert-status.json` Elasticsearch `_template` pre-declared a
    `match_body` object mapping (implicitly `enabled: true`) for
    `elastalert_status*` indices, which collided with ElastAlert2's own
    official mapping (`match_body: {enabled: false}` — alert bodies are stored
    but not indexed, by design) and made `elastalert-create-index` fail with a
    500 on every start. Deleted the legacy template (its only custom fields,
    `z_logstash_pipeline`/`etl_pipeline`, were unreferenced anywhere else in
    the pipeline) rather than trying to reconcile two mapping authorities for
    the same index.
  - Verified end-to-end on the local Docker Desktop stack, including a full
    `docker compose --profile alert down -v && up -d --build` clean-slate
    rebuild (confirming the template fix persists on a fresh deploy, not just
    the live cluster it was patched on): `elastalert_status`
    (+ `_status`/`_silence`/`_error`/`_past`) indices create with no error, all
    2332 rules (23 curated + 2309 Sigma-derived) load and query, and a seeded
    test Sysmon document matching the curated `helk_sysmon_bits.yml` rule
    produced a real alert (`1 query hits, 1 matches, 1 alerts sent`) within
    one query cycle.
- **Phase 3 — done.** Spark 4.1.2 (Scala 2.13) standalone cluster
  (`helk-spark-master`/`helk-spark-worker`) + a rebuilt `helk-jupyter` with
  GraphFrames 0.12.1, gated behind the `notebook` Compose profile
  (`docker compose --profile notebook up -d --build`).
  - Version correction vs. this document's original §3 recommendation: Spark
    3.5.8/Scala 2.12 was the right call when that research was done, but by
    Phase 3 implementation time `quay.io/jupyter/pyspark-notebook`'s newest
    tag had moved on to `spark-4.1.2` and no `spark-3.5.x` tag remained
    published; GraphFrames 0.12.1 itself hadn't changed, but its
    Spark-4/Scala-2.13 artifact (`graphframes-spark4_2.13`) is what's current
    now, not the `graphframes-spark3_2.12` one originally named. Re-verified
    live (Quay tag API, Maven Central, PyPI) rather than assumed from the
    original pass — see §3's updated table rows.
  - `helk-spark-master` and `helk-spark-worker` are built from the *same*
    `quay.io/jupyter/pyspark-notebook:spark-4.1.2` image tag as the Jupyter
    driver, not a generic Spark image. PySpark requires the driver and
    executors to run matching Python major.minor versions; reusing one image
    tag guarantees that without hand-pinning a Python build to track the
    Jupyter image's conda Python across upgrades — this also let
    `helk-spark-worker`'s old hand-installed Miniconda `python=3.7.5` (a
    manual version-matching workaround for the same underlying problem) be
    deleted entirely. `helk-spark-base` is deleted; both master and worker
    keep the existing foreground `spark-class`-invoking entrypoint scripts
    (Spark's own `sbin/start-master.sh`/`start-worker.sh` daemonize and
    return, which would exit the container).
  - GraphFrames needs two jars, not one — `graphframes-spark4_2.13` (core) +
    `graphframes-graphx-spark4_2.13` (its one runtime dependency,
    per graphframes.io's own install docs for offline/Docker installs) —
    baked into `helk-jupyter`'s `$SPARK_HOME/jars` at build time and added to
    a new `spark-defaults.conf`'s `spark.jars` so every notebook-created
    SparkSession gets them automatically (matching the old, invisible
    `jupyter-hunter` base image's behavior — none of the tutorial/Sigma
    notebooks configure `spark.jars`/`--packages` themselves).
  - Postgres-backed Hive metastore (§4 item 2) carried forward as required:
    reimplemented as a docker-stacks `before-notebook.d/` startup hook
    (`10-hive-metastore.sh`) rather than a custom `ENTRYPOINT` override, so
    the base image's own tini/`start.sh` init path still runs. Fixed two
    latent bugs found while porting it: the Postgres major version was
    hardcoded to `10` (now detected dynamically, since the new base's Ubuntu
    release ships a newer one) and `PGDATA` was hardcoded to
    `/home/jupyter/...` (the new base's user is `jovyan`, not `jupyter`).
    `PGDATA` is persisted in a named volume (`jupyter-hive-metastore`) so
    table definitions survive container recreation, not just restarts.
  - Jupyter path auth (§5 decision #1, resolved): Nginx gets a new
    `/jupyter/` location proxying to `helk-jupyter:8888`, gated by Jupyter's
    own `JUPYTER_TOKEN` (in `.env`) rather than a second htpasswd layer. Since
    `helk-jupyter` only exists under the `notebook` profile, the proxy target
    is resolved through a variable + Docker's embedded DNS (`resolver
    127.0.0.11`) instead of a static `proxy_pass` hostname — a static
    hostname would make Nginx fail to start whenever the profile is off and
    the container doesn't exist. (Also caught during verification: Nginx
    doesn't pick up a bind-mounted config edit without a reload — the first
    test against a container that had been running since before this change
    fell through to Kibana instead of Jupyter for exactly that reason.)
  - Six real bugs found and fixed during boot testing (beyond the version
    corrections above), each the kind that only surfaces by actually booting
    the stack, not by reading the Dockerfiles:
    1. `helk-spark-worker` couldn't create `$SPARK_HOME/work`
       (`AccessDeniedException`) — the base image's `$SPARK_HOME` isn't
       writable by the non-root `jovyan` user by default; fixed with an
       explicit `chown` at build time.
    2. Both `helk-spark-master`/`worker` inherited the base image's own
       Jupyter-HTTP-endpoint healthcheck, which left them permanently
       "unhealthy" despite running fine — neither service runs Jupyter, so
       set `HEALTHCHECK NONE` on both.
    3. `10-hive-metastore.sh`'s Postgres-bindir auto-detection used
       `find -maxdepth 2`, one level too shallow for the real path
       (`/usr/lib/postgresql/<ver>/bin/initdb` is 3 levels down) — silently
       resolved to `.`, and combined with the script using `set -e` while
       being *sourced* (not executed) by docker-stacks' `start.sh`, a failed
       `pg_ctl` call there silently killed the entire container's startup.
       Fixed the depth and dropped `set -e` from the sourced script.
    4. The `PGDATA` existence check (`[ ! -d "$PGDATA" ]`) never triggered
       `initdb`, because `PGDATA` is a mounted named volume — Docker always
       creates the mountpoint directory even when empty. Fixed to check for
       `PGDATA/PG_VERSION` (a file `initdb` actually creates) instead.
    5. `initdb` then failed with "could not change permissions" because a
       freshly created named volume inherits ownership from whatever
       already exists at that path in the image, and nothing did yet; fixed
       by pre-creating `${HOME}/srv/pgsql` with `jovyan` ownership in the
       Dockerfile so the volume seeds correctly on first mount.
    6. Postgres itself then failed with "could not create lock file
       .../.s.PGSQL.5432.lock: Permission denied" — apt's `postgresql`
       package owns `/var/run/postgresql` as the `postgres` system user, but
       Postgres runs as `jovyan` here; fixed with a `chown` at build time
       (this is the one piece of the original image's Dockerfile — `chown
       ${USER} /run/postgresql` — that turned out to still be load-bearing).
  - Notebook verification depth (§5 decision #2, resolved): spot-checked
    rather than fixing all 378 Sigma-derived notebooks individually. Findings
    below, in rough order of how systemic they are.
  - **PySpark itself wasn't importable at all**, in any of `helk-jupyter`/
    `helk-spark-master`/`helk-spark-worker` — despite the base image's name,
    `quay.io/jupyter/pyspark-notebook` installs Spark's JVM side but neither
    pip-installs a `pyspark` package nor puts `$SPARK_HOME/python` on
    `PYTHONPATH`. Every notebook that does `from pyspark.sql import
    SparkSession` (all 7 tutorials, an unknown fraction of the 378 Sigma
    notebooks — see below) would have failed at the first cell. Fixed by
    pointing `PYTHONPATH` at the bundled `$SPARK_HOME/python` (guarantees an
    exact version match with the driver's own Spark install, unlike a second
    `pip install pyspark`) on both the driver and the worker (executors spawn
    a `python3 -m pyspark.worker` subprocess for Python tasks and need the
    same fix).
  - **The 378 Sigma-derived notebooks (`notebooks/sigma/`) don't use PySpark
    at all** — they query Elasticsearch directly via the raw
    `elasticsearch`/`elasticsearch_dsl` Python clients (confirmed by
    inspecting a 6-notebook sample spanning the three largest prefixes: `win_`
    216, `sysmon_` 51, `powershell_` 14). Neither package existed anywhere in
    the image, so none of the 378 could import their own dependencies as
    shipped — installed `elasticsearch==8.18.1`/`elasticsearch-dsl==8.18.0`
    (the last release of `elasticsearch-dsl`, which pins `elasticsearch<9`;
    running a Spark/ES client one major behind the 9.4.3 server is within
    Elastic's documented compatibility window, not a mismatch). This is an
    image-level fix (every one of the 378 needed it identically), distinct
    from the per-notebook content fixes described next, which is why it was
    done now rather than deferred.
  - With that dependency gap closed, running the sampled notebook
    (`win_account_discovery.ipynb`) end-to-end surfaces the same root cause
    found in the demos/tutorials below: `Elasticsearch(['http://...'])` is
    called with no credentials at all (not even the demos'/tutorials'
    partial attempt), so every one of the 378 gets a hard
    `AuthenticationException` (401) as soon as it queries. This is
    mechanical and near-identical to fix across all 378 (add
    `basic_auth=("elastic", os.environ["ELASTIC_PASSWORD"])` to each
    `Elasticsearch(...)` constructor) — flagged as the highest-value,
    lowest-risk item for a future full pass, but not applied here per the
    "spot-check, don't fix all 378" scope decision.
  - **GraphFrames 0.12.1 itself is confirmed working end-to-end on Spark
    4.1.2**, distributed across the real `helk-spark-master`/`worker`
    cluster (not local mode): the tutorial notebook's synthetic-data smoke
    test (`GraphFrame(v, e)`, `.inDegrees`, edge filtering/counting) executed
    cleanly with correct output. This was the actual thing Phase 3 needed to
    prove and it holds — the two-jar install (§3) and the driver/executor
    Python-parity approach are both validated by this, not just by
    "the jar loads."
  - **The Elasticsearch-Spark connector (`elasticsearch-spark-30_2.13:9.0.3`)
    also confirmed working against Spark 4.1.2 and ES 9.4.3** once given
    credentials (`es.net.http.auth.pass`) — resolving the risk flagged
    earlier in this phase (Elastic has never published a Spark-4-targeted
    build; empirically this one still works over the DataSource V1 path this
    notebook uses).
  - Fixed the 3 demo notebooks (`notebooks/demos/`) and the 3
    Elasticsearch-reading tutorials (`05`/`06`/`07`) the same way: added
    `.option("es.net.http.auth.pass", os.environ["ELASTIC_PASSWORD"])` (they
    had `es.net.http.auth.user` but no password at all — harmless when the
    old stack ran with security disabled, a hard authentication failure now
    that Phase 1 turned ES auth on). The pandas demo's `from pandas.io.json
    import json_normalize` was fixed to `pd.json_normalize` (removed in
    pandas 2.0, a hard `ImportError`, not a soft deprecation). Small enough
    numbers (6 notebooks total) to fix directly rather than just flag.
  - **Genuine content bug found, not fixed**: the GraphFrames tutorial
    references a `process_parent_name` field that Logstash's own pipeline
    has never produced (confirmed via `helk-logstash/pipeline/*.conf` — the
    real field is `process_parent_name`'s apparent replacement,
    `process_parent_path`). This is a real stale-notebook bug, distinct from
    the next point.
  - **Verification limit, not a bug**: the same notebook's later cells
    (motifs over real Sysmon data) also failed to resolve `process_parent_guid`
    — but that field name *is* correct and current per the Logstash pipeline
    (`ParentProcessGuid` → `process_parent_guid`). The failure there is
    because this dev deployment's `logs-endpoint-winevent-sysmon-*` index
    has exactly one document (the synthetic alert-test doc seeded during
    Phase 2 verification, not a realistic Sysmon event) and
    `logs-endpoint-winevent-security-*` has zero — Spark's schema inference
    over a near-empty index can't resolve fields it never sees. Meaningfully
    verifying notebook behavior against real data requires actual
    Winlogbeat-sourced Sysmon telemetry flowing through the pipeline, which
    this local verification environment doesn't have. Flagging this
    explicitly rather than either claiming full verification or spending
    effort chasing a false "stale field name" lead.
  - **Follow-up scope for a future full notebook-fix pass** (requested by the
    user to be documented now rather than done as part of this phase): the
    378 Sigma-derived notebooks were generated by the old, dead `sigmac`
    tooling. A full pass would need to (1) add ES auth credentials to all 378
    (mechanical, see above — the single highest-value item), (2) regenerate
    or hand-port them from the current Sigma rule set/pySigma tooling rather
    than patching stale generated files, since the underlying `sigmac` tool
    is gone, (3) audit any GraphFrames algorithm usage against the 0.12.1 API
    (connected-components changed its checkpoint-directory requirements and
    return schema since the pre-0.11 API these were written against), and
    (4) re-verify field-name references like `process_parent_name` above
    against the current Logstash pipeline — which in turn needs real
    Winlogbeat/Sysmon telemetry flowing through the stack to verify
    meaningfully, not just synthetic test documents. This is a materially
    larger effort than Phase 3 itself, consistent with §5's original framing
    of it as "arguably its own project."
- **Phase 4 — done.** Resolved §5 decision #4 first (see below), then
  rewrote all three lifecycle scripts as thin wrappers over the single
  `compose.yaml`, and deleted the two scripts that only existed to serve
  the dropped bare-metal path.
  - **§5 decision #4, resolved 2026-07-17: drop bare-metal provisioning.**
    User chose to stop supporting root/apt/yum/systemd/sysctl/firewalld
    Linux-server installs and focus modernization on the Compose files
    themselves, over porting that provisioning to Compose v2. This was also
    the only branch verifiable in this environment — Docker Desktop/Windows
    can't exercise `apt`, `systemctl`, `sysctl`, `/proc/meminfo`, or
    `firewalld`, so a ported bare-metal installer would have shipped without
    the boot-test verification every prior phase had.
  - `helk_install.sh`, `helk_update.sh`, `helk_remove_containers.sh` were
    rewritten from scratch rather than patched — patching would have meant
    keeping the `$EUID -ne 0` root gate, the `helk-kibana-*-basic.yml`
    build-choice menu (those files don't exist; there's one `compose.yaml`
    with `alert`/`notebook` profiles), `install_htpasswd` (dropped in Phase
    1), and the `docker-compose` v1 binary calls, none of which apply to the
    current design.
  - `helk_docker_install.sh` (installed Docker itself) and
    `helk_setup_firewall.sh` (CentOS/firewalld only) were deleted outright —
    both were pure bare-metal provisioning with no equivalent in the
    Compose-v2-wrapper design.
  - All three surviving scripts now: `cd` to their own directory via
    `dirname "${BASH_SOURCE[0]}"` (fixing the fragile relative-path reads —
    `../.git/refs/heads/master` in the old `helk_install.sh`, and the
    `../configs/firewalld/helk.xml` copy in the deleted firewall script,
    both of which assumed a specific invocation cwd); accept repeatable
    `--profile <name>` flags matching `docker compose`'s own flag, instead
    of a numbered 1-4 build menu; and require the Compose v2 plugin
    (`docker compose version`) rather than a pinned `docker-compose` v1.27.4
    binary (the original pin was to dodge a glibc issue in 1.28 that is long
    since irrelevant — v1 itself is EOL).
  - `helk_install.sh`: on a missing `.env`, copies `.env.example` and exits
    asking the user to fill in real secrets rather than prompting
    interactively for a Kibana password with a 90-second timeout-then-default
    (as the old script did) — matches the `.env`-based config model from
    Phase 1 instead of layering a second, script-driven credential flow on
    top of it. Warns (but doesn't block) if `.env` still has `changeme_*`
    placeholders. Boots via `docker compose --profile ... up -d --build`,
    waits for Logstash's "Restored connection to ES instance" log line (kept
    from the original — still a real, useful signal), and prints a final
    summary with the actual reachable URLs (Kibana via Nginx TLS and via its
    direct port mapping, Spark Master UI and Jupyter's URL/token when
    `notebook` is active) — no more Zookeeper/KSQL lines, both gone since
    Phase 1.
  - `helk_update.sh`: the two real bugs named in §2.2/§5.4 are both fixed.
    (1) The destructive `git clean -d -fx .` — which silently deletes every
    untracked file as part of a routine "update" — is gone; the script now
    runs `git status --porcelain` first and refuses to touch anything if the
    tree isn't clean, printing exactly what's dirty and telling the user to
    handle it themselves. (2) The hardcoded `../.git/refs/heads/master` read
    (also doubly wrong here since this repo's branch is `main`, not
    `master`) is replaced with `git rev-parse --abbrev-ref HEAD` and
    `git config branch.<name>.remote`, so it works on whatever branch/remote
    the clone actually has — also fixing the old script's habit of adding a
    hardcoded remote pointing at the upstream `Cyb3rWard0g/HELK.git`, which
    is wrong for a fork (verified this clone's `origin` already points at
    the user's own fork). Pulls fast-forward-only (`git pull --ff-only`) and
    refuses if the branch has diverged, rather than the old script's
    unconditional `git pull`.
  - `helk_remove_containers.sh`: the old version made the user type back one
    of four legacy compose filenames from memory, then force-removed any
    local image matching a broad grep across
    `otrf|cyb3rward0g|helk|logstash|kibana|elasticsearch|cp-ksql` — a
    pattern that could just as easily match an unrelated image on the same
    Docker host. Replaced with `docker compose down`, scoped to this
    project's own containers by construction; `--volumes` and `--images` are
    separate, explicit, confirmed-by-default flags rather than always-on
    behavior.
  - Verification: `bash -n` on all three (clean); ran `--help` and an
    unknown-flag case on each to confirm argument parsing and usage text;
    exercised the missing-`.env` bootstrap path in an isolated copy of the
    repo (confirms it copies `.env.example` and exits without proceeding);
    ran `helk_update.sh` against this actual repo mid-Phase-4 (with real
    uncommitted changes on disk) and confirmed it correctly found the repo
    root, detected the dirty tree, printed the exact files involved, and
    exited without touching anything — the safety check the whole rewrite
    was centered on. Did **not** run a live `helk_install.sh`/
    `helk_remove_containers.sh` end-to-end boot, since that would just
    re-exercise the same `docker compose up`/`down` paths already verified
    directly in Phases 1-3; the wrapper logic itself (flag parsing, `.env`
    handling, the git safety check) is what's new here and what got tested.
  - `docs/installation.md` was rewritten to match: Docker+Compose v2 as a
    prerequisite instead of something the script installs, `.env`-based
    configuration, the `--profile` flag convention, and the actual
    URLs/ports this stack exposes (no more Zookeeper/KSQL references).

§5 decisions #1 (Jupyter auth), #2 (notebook verification depth), and #4
(lifecycle script scope) were all resolved during Phases 3-4 (see above).
Decision #3 (Kibana saved objects) remains open and does not gate any phase
in this plan — it's unscheduled future work.
