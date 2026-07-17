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
| Spark | **3.5.8**, Scala 2.12 | High |
| GraphFrames | `io.graphframes:graphframes-spark3_2.12:0.12.1` (Scala/Java side) + `graphframes-py==0.12.1` (Python side) — this exact pairing is the literal dependency declared in the published artifact's POM, not an inference | High |
| Jupyter base image | Rebuild from `quay.io/jupyter/pyspark-notebook:spark-3.5.3` (Docker Hub `jupyter/pyspark-notebook` is no longer updated; the project moved to `quay.io/jupyter/*`); add GraphFrames jar + `graphframes-py` on top; use docker-stacks' documented `start-notebook.py`/`start.sh` instead of the vanished `jupyter-cmd.sh` | High |
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

## 5. Open decisions (not yet resolved)

1. **Jupyter path auth.** Once htpasswd is dropped from the Kibana path in
   favor of native ES/Kibana login, `/jupyter` has no equivalent gate other
   than Jupyter's own token. Two options on the table:
   - Generate a separate htpasswd credential **at deploy time only** (never
     committed) applied just to the `/jupyter` Nginx location block.
   - Rely solely on Jupyter's built-in token auth (matches the original
     repo's behavior for the notebook build variant), accepting the same
     weaker posture it always had.
2. **Notebook verification depth.** All 378 Sigma-derived notebooks plus the
   GraphFrames tutorial notebook were written against ~2020-era GraphFrames
   APIs (pre-0.11 connected-components refactor). Decision needed:
   - Modernize the image and spot-check a representative sample plus the
     GraphFrames tutorial notebook, flagging systematic breaks without fixing
     all 378 individually, **or**
   - A full pass fixing every one of the 378 notebooks — a materially larger
     effort, arguably its own project.
3. **Kibana saved objects.** Confirm whether the ~85 existing dashboards/
   visualizations are still wanted before investing in either the staged
   7.17→8.19→9.4 migration or selective Lens rebuilds — some may be stale
   2021-era demo content not worth carrying forward at all.
4. **How far to take the install/lifecycle scripts.** `helk_install.sh` /
   `helk_update.sh` / `helk_remove_containers.sh` target Linux server
   deployment (root, systemd, apt/yum) — separate from whether we ever run
   this locally via Docker Desktop. Worth deciding whether to keep
   supporting bare-metal/VM Linux installs at all, or to focus modernization
   effort on the Compose files themselves and treat the shell scripts as
   secondary.

---

## 6. Proposed phased sequencing (not started)

Each phase would end with an actual `docker compose up` boot test on the
local Docker Desktop (confirmed available: Docker Desktop 4.82, Compose
v5.3, WSL2 backend).

- **Phase 0** — hygiene: strip the committed htpasswd credential (generate
  only at deploy time going forward), fix the fatal stale zen-discovery
  setting.
- **Phase 1** — core bootable slice: Elasticsearch + Kibana + Logstash +
  Kafka (KRaft) + Nginx (TLS-only), all built from local Dockerfiles at the
  target versions above, on one consolidated `compose.yaml`.
- **Phase 2** — alerting: ElastAlert2 + new Sigma tooling, as the `alert`
  Compose profile.
- **Phase 3** — analytics: Spark 3.5.8/GraphFrames 0.12.1 + rebuilt Jupyter
  image, as the `notebook` Compose profile; verification pass scoped per
  the decision in §4.2.
- **Phase 4** — lifecycle scripts: modernize for Compose v2, fix the
  destructive `git clean -d -fx` in `helk_update.sh`, fix the fragile
  relative-path git-ref read, scoped per the decision in §4.4.

No implementation has started. This document reflects research only.
