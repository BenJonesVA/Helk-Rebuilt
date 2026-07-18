# HELK Rebuilt

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![stability-wip](https://img.shields.io/badge/stability-work--in--progress-orange.svg)](https://github.com/mkenney/software-guides/blob/master/STABILITY-BADGES.md#work-in-progress)
[![Fork of HELK](https://img.shields.io/badge/fork%20of-Cyb3rWard0g%2FHELK-blueviolet.svg)](https://github.com/Cyb3rWard0g/HELK)
[![Progress](https://img.shields.io/badge/progress-~85%25%20(Phase%203%20of%204)-yellow.svg)](#status-work-in-progress-~85-complete)

**HELK Rebuilt** is a from-scratch modernization of **HELK (The Hunting
ELK)** — one of the first open source hunt platforms to combine SQL
declarative querying, graph analytics, structured streaming, and Jupyter
Notebook/Apache Spark-based machine learning on top of an ELK stack. The
original project ([Cyb3rWard0g/HELK](https://github.com/Cyb3rWard0g/HELK))
hasn't had a commit since May 2021, and nearly every component it depends on
— Elasticsearch/Kibana/Logstash 7.6.2, Kafka 2.4.1 on ZooKeeper, Spark
2.4.5, an unmaintained personal Jupyter base image, Yelp's abandoned
`elastalert`, and a Sigma-rule fork that no longer exists — is now years out
of date or gone outright.

This project keeps HELK's actual value — the streaming ingestion pipeline,
ECS/OSSEM/ATT&CK-enriched detection content, and Spark/GraphFrames-based
graph hunting in Jupyter — and rebuilds the infrastructure underneath it on
currently maintained software.

## Status: Work In Progress (~85% complete)

🚧 **This project is a work in progress.** The core stack, alerting, and
analytics all boot clean on currently maintained software; only
lifecycle-script modernization is not started. Full technical detail —
inventory, version decisions, open questions — lives in
**[MODERNIZATION.md](MODERNIZATION.md)**.

Progress by phase (percentage is phase count, not effort-weighted — Phases 1,
2, and 3 were the largest chunks of work):

| Phase | Scope | Status |
|---|---|---|
| 0 — Hygiene | Strip committed htpasswd credential, fix fatal stale ES discovery setting | ✅ Done |
| 1 — Core bootable stack | Elasticsearch 9.4.3, Kibana 9.4.3, Logstash 9.4.3, Kafka 4.3.1 (KRaft, no Zookeeper), Nginx (TLS), consolidated into one `compose.yaml`. Verified with a clean `docker compose down -v && up --build`: all services healthy, Kibana reachable through Nginx over HTTPS, all 5 Kafka topics created, Logstash's pipelines run error-free. Along the way, converted ~22 of HELK's legacy Elasticsearch index templates to composable templates after finding they collided with Elastic's built-in `logs-*-*` reserved template namespace on 9.x. | ✅ Done |
| 2 — Alerting | ElastAlert2 2.30.0 + a new `sigma-cli`/`pySigma-backend-elasticsearch` pipeline replacing the dead Sigma fork, gated behind the `alert` Compose profile. Converts 2,309 current SigmaHQ/sigma Windows rules to ElastAlert2 rules via a custom pySigma field-mapping pipeline ported from the legacy OSSEM config, plus the 23 curated `helk_*` rules. Verified with a clean `docker compose --profile alert down -v && up --build`: all 2,332 rules load, and a seeded test event produced a real fired alert end-to-end. | ✅ Done |
| 3 — Analytics | Spark 4.1.2 (Scala 2.13) standalone cluster + GraphFrames 0.12.1 + a rebuilt Jupyter image, gated behind the `notebook` Compose profile. Verified with a clean `docker compose --profile notebook down -v && up --build`: worker registers with master, PySpark imports on both driver and executors, GraphFrames' core graph algorithms run correctly on the real distributed cluster, the Postgres-backed Hive metastore provisions and persists, and Jupyter is reachable through Nginx with token auth. | ✅ Done |
| 4 — Lifecycle scripts | Modernize `helk_install.sh`/`helk_update.sh`/`helk_remove_containers.sh` for Compose v2, fix the destructive `git clean -d -fx`, fix fragile relative-path git-ref read | ⬜ Not started |

Confirmed design choice from Phase 1: Elasticsearch runs with authentication
on but TLS disabled between containers on the internal Docker network (TLS
is terminated only at the Nginx edge). This deviates from
MODERNIZATION.md's original recommendation but was confirmed as intentional
for this single-node, internal-only deployment — see
[MODERNIZATION.md §6](MODERNIZATION.md#6-proposed-phased-sequencing).

Scope note from Phase 2: converting Sigma's OSSEM field mappings to pySigma
is a full 1:1 port for the ~150 simple field renames, but ~20 fields whose
legacy mapping varied by Windows EventID were deliberately collapsed to a
single dominant value rather than reproduced with full per-EventID fidelity —
see [MODERNIZATION.md §6](MODERNIZATION.md#6-proposed-phased-sequencing) for
which fields and why. Also, the upstream Sigma repo no longer has a top-level
`apt` rule category, so only `rules/windows/` is converted.

Version correction from Phase 3: MODERNIZATION.md originally targeted Spark
3.5.8; by implementation time the Jupyter base image's newest published tag
had moved on to Spark 4.1.2 with no 3.5.x tag left available, so that's what
got built and verified instead (GraphFrames 0.12.1 itself didn't change,
just which Spark/Scala-targeted artifact of it is current) — see
[MODERNIZATION.md §6](MODERNIZATION.md#6-proposed-phased-sequencing).

Scope note from Phase 3: per an explicit user decision, the 378 Sigma-derived
notebooks were spot-checked rather than individually fixed. All 378 needed
(and got) an image-level dependency fix (the `elasticsearch`/`elasticsearch-dsl`
Python packages weren't installed anywhere), but a per-notebook fix — every
one of them calls the Elasticsearch client with no auth credentials, so all
378 currently fail with a 401 — was deliberately left for a future full pass.
See [MODERNIZATION.md §6](MODERNIZATION.md#6-proposed-phased-sequencing) for
the full spot-check findings and exactly what that future pass would need to
do.

Two scope decisions in [MODERNIZATION.md §5](MODERNIZATION.md#5-open-decisions)
remain unresolved and gate Phase 4 only: whether to carry forward Kibana's
~85 legacy saved objects, and how far to modernize the install/lifecycle
scripts. (The two decisions that gated Phase 3 — Jupyter path auth and
notebook verification depth — were resolved during Phase 3; see above.)

## Goals

Carried over from the original HELK:

* Provide an open source hunting platform to the community and share the
  basics of Threat Hunting.
* Expedite the time it takes to deploy a hunt platform.
* Improve the testing and development of hunting use cases in an easier and
  more affordable way.
* Enable Data Science capabilities while analyzing data via Apache Spark,
  GraphFrames & Jupyter Notebooks.

Specific to this rebuild:

* Replace every abandoned or unmaintained dependency (dead base images,
  floating/stale Docker tags, a deleted Sigma rule fork, EOL Python) with
  currently maintained equivalents, rebuilt from the project's own
  Dockerfiles instead of pulled from frozen third-party images.
* Preserve HELK's detection/analytics capabilities rather than just bumping
  version numbers — including deliberately replacing components (e.g. the
  Sysmon/network correlation currently done in ksqlDB) rather than letting
  functionality quietly disappear along with the software that implemented
  it. See [MODERNIZATION.md §4](MODERNIZATION.md#4-functionality-at-risk-of-loss--replacement-candidates)
  for the specific items being tracked.
* Move onto Kafka's KRaft mode (no ZooKeeper), native Elasticsearch/Kibana
  security (free since the Basic license, on by default in 8+), and
  actively maintained community successors for anything upstream abandoned
  (ElastAlert2, `sigma-cli`, mainline `SigmaHQ/sigma`).

## Credit

HELK Rebuilt is an independent, unofficial fork — it is **not** an official
continuation of, or endorsed by, the original project. All credit for the
original design, architecture, and detection content goes to:

* **Roberto Rodriguez** — [@Cyb3rWard0g](https://twitter.com/Cyb3rWard0g) /
  [@THE_HELK](https://twitter.com/THE_HELK) — original author and creator of
  HELK.
* **Nate Guagenti** — [@neu5ron](https://twitter.com/neu5ron) — original
  committer.

Please refer to the [original HELK repository](https://github.com/Cyb3rWard0g/HELK)
and its [documentation site](https://thehelk.com) for the project's history
and original design rationale.

## Docs

* [MODERNIZATION.md](MODERNIZATION.md) — this fork's inventory, target
  architecture, open decisions, and phased plan.
* Original HELK: [Introduction](https://thehelk.com/intro.html) ·
  [Installation](https://thehelk.com/installation.html)

## Resources

* [Welcome to HELK! : Enabling Advanced Analytics Capabilities](https://cyberwardog.blogspot.com/2018/04/welcome-to-helk-enabling-advanced_9.html)
* [Setting up a Pentesting.. I mean, a Threat Hunting Lab - Part 5](https://cyberwardog.blogspot.com/2017/02/setting-up-pentesting-i-mean-threat_98.html)
* [Apache Spark](https://spark.apache.org/docs/latest/index.html) ·
  [Spark Standalone Mode](https://spark.apache.org/docs/latest/spark-standalone.html)
* [GraphFrames](https://graphframes.io) ·
  [An Integrated API for Mixing Graph and Relational Queries](https://cs.stanford.edu/~matei/papers/2016/grades_graphframes.pdf) ·
  [Graph queries in Spark SQL](https://www.slideshare.net/SparkSummit/graphframes-graph-queries-in-spark-sql)
* [Elastic Products](https://www.elastic.co/products) ·
  [Elasticsearch Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
* [SigmaHQ/sigma](https://github.com/SigmaHQ/sigma) ·
  [sigma-cli](https://github.com/SigmaHQ/sigma-cli)
* [ElastAlert2](https://github.com/jertel/elastalert2)

## License: GPL-3.0

HELK Rebuilt remains licensed under the GNU General Public License v3.0, the
same license as the original HELK project. See [LICENSE](LICENSE).
