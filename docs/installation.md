# Installation

## Requirements

* **Docker Engine or Docker Desktop**, with the **Compose v2 plugin**
  (`docker compose version` must work — the standalone `docker-compose` v1
  binary is not supported). This project no longer installs Docker for you;
  install it yourself first: <https://docs.docker.com/get-docker/>.
* **Processor/OS Architecture:** 64-bit (x86_64/AMD64). Elasticsearch's
  bundled ML programs require SSE4.2 instructions.
* **RAM:** roughly 5GB for the core stack, +2-3GB if you enable the `alert`
  profile, +3GB if you enable the `notebook` profile (Spark + Jupyter).
* **Disk:** 20GB for testing, 100GB+ for any real data volume.
* **Network:** internet access to pull/build images on first run. If you
  intend to send data from other hosts (e.g. Winlogbeat → Kafka), the
  `ADVERTISED_LISTENER` value in `.env` needs to be an address those hosts
  can reach.

## Download

```bash
git clone <this repo's URL>
cd helk-rebuilt/docker
```

## Configure

Copy the example environment file and fill in real values (passwords,
Kibana encryption keys, `JUPYTER_TOKEN`, etc). `helk_install.sh` will do this
copy for you automatically on first run if `.env` doesn't exist yet, then
stop and ask you to edit it:

```bash
cp .env.example .env
$EDITOR .env
```

See the comments in `.env.example` for what each value is used for and how
to generate real secrets (e.g. Kibana encryption keys via
`docker run --rm docker.elastic.co/kibana/kibana:<version> bin/kibana-encryption-keys generate`).

## Install

The stack is a single `compose.yaml` with two optional Compose **profiles**:

* `alert` — ElastAlert2 + Sigma-derived detection rules
* `notebook` — Spark standalone cluster + Jupyter/GraphFrames

`helk_install.sh` is a thin wrapper around `docker compose` that validates
your environment, boots the stack, waits for Logstash to connect to
Elasticsearch, and prints a summary of how to reach everything:

```bash
./helk_install.sh                                    # core stack only
./helk_install.sh --profile alert                     # + alerting
./helk_install.sh --profile alert --profile notebook  # + alerting + notebooks
```

Example output:

```
[HELK-INSTALL] Building and starting HELK (profiles: alert notebook)...
[HELK-INSTALL] Waiting for Logstash to connect to Elasticsearch...

***********************************************************************
  HELK is up
***********************************************************************
  Kibana (via Nginx, TLS):  https://localhost/
  Kibana (direct):          http://localhost:5601/
  Login:                    user 'elastic', password = ELASTIC_PASSWORD in .env
  ElastAlert2:              running (no UI; alerts land in Elasticsearch/Slack per rule config)
  Spark Master UI:          http://localhost:8080/
  Jupyter:                  https://localhost/jupyter  (token: <your JUPYTER_TOKEN>)

  Stop everything:   ./helk_remove_containers.sh --profile alert --profile notebook
  Pull in updates:    ./helk_update.sh --profile alert --profile notebook
```

## Monitor startup

```bash
docker compose ps
docker compose logs --follow --tail 20 helk-elasticsearch
docker stats
```

## Update

`helk_update.sh` fetches your current branch from `origin`, refuses to touch
anything if you have uncommitted or untracked changes, fast-forwards only
(it will not silently merge or rebase), and then rebuilds:

```bash
./helk_update.sh --profile alert --profile notebook
```

Pass `-y`/`--yes` to skip the confirmation prompt (useful in automation).

## Remove

`helk_remove_containers.sh` wraps `docker compose down`, scoped to this
project only:

```bash
./helk_remove_containers.sh --profile alert --profile notebook           # stop + remove containers
./helk_remove_containers.sh --profile alert --profile notebook --volumes  # + delete all data (destructive)
./helk_remove_containers.sh --images                                      # + delete locally built images
```

`--volumes` deletes Elasticsearch data, Kafka data, Nginx TLS certs, the
Sigma rules cache, and the Jupyter Hive metastore permanently. You'll be
asked to confirm unless `-y`/`--yes` is passed.
