#!/bin/bash

# HELK script: helk_install.sh
# HELK script description: Boot the HELK stack via Docker Compose v2
# HELK build Stage: Alpha
# License: GPL-3.0

# Phase 4 rewrite: this is now a thin wrapper over `docker compose`, not a
# bare-metal provisioner. It assumes Docker Engine/Desktop + the Compose v2
# plugin are already installed - the old root/apt/yum/systemd/sysctl/
# firewalld/htpasswd provisioning is gone, matching the decision to stop
# supporting bare-metal installs and focus on the single compose.yaml +
# `alert`/`notebook` profiles built in Phases 0-3. See MODERNIZATION.md
# Phase 4 / §5 decision #4.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INFO="[HELK-INSTALL]"
ERR="[HELK-INSTALL-ERROR]"

usage() {
  cat <<EOF
Usage: $0 [--profile alert] [--profile notebook] [-h|--help]

Boots the HELK core stack (Elasticsearch, Kibana, Logstash, Kafka, Nginx) via
'docker compose'. Optional components are opt-in via repeatable --profile
flags, matching docker compose's own flag:

  --profile alert     ElastAlert2 + Sigma-derived detection rules
  --profile notebook  Spark standalone cluster + Jupyter/GraphFrames

Examples:
  $0                                        core stack only
  $0 --profile alert                        core stack + alerting
  $0 --profile alert --profile notebook     everything
EOF
  exit 1
}

ORIGINAL_ARGS=("$@")
PROFILES=()
PROFILE_NAMES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || usage
      PROFILES+=(--profile "$2")
      PROFILE_NAMES+=("$2")
      shift 2
      ;;
    -h|--help) usage ;;
    *)
      echo "$ERR Unknown option: $1"
      usage
      ;;
  esac
done

# *********** Pre-flight checks ***************
command -v docker >/dev/null 2>&1 || {
  echo "$ERR docker was not found on PATH. Install Docker Desktop or Docker Engine first: https://docs.docker.com/get-docker/"
  exit 1
}
docker compose version >/dev/null 2>&1 || {
  echo "$ERR 'docker compose' (the Compose v2 plugin) is not available. Update Docker, or install the compose-plugin package."
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "$ERR Could not talk to the Docker daemon. Is Docker running, and do you have permission to use it?"
  exit 1
}

if [[ ! -f compose.yaml ]]; then
  echo "$ERR compose.yaml not found in $SCRIPT_DIR - this script must live in the same directory as compose.yaml."
  exit 1
fi

if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    echo "$INFO Created .env from .env.example."
    echo "$INFO Edit .env now and set real values for every 'changeme_*' placeholder (passwords, Kibana encryption keys, JUPYTER_TOKEN, etc), then re-run this script."
    exit 1
  else
    echo "$ERR No .env or .env.example found in $SCRIPT_DIR. Cannot continue."
    exit 1
  fi
fi

PLACEHOLDERS=$(grep -E '^[A-Z_]+=changeme' .env || true)
if [[ -n "$PLACEHOLDERS" ]]; then
  echo "$INFO Warning: .env still has default placeholder values for:"
  echo "$PLACEHOLDERS" | sed 's/^/    /'
  echo "$INFO Continuing anyway, but set real values before exposing this deployment beyond local testing."
fi

# *********** Build and start ***************
echo "$INFO Building and starting HELK (profiles:${PROFILE_NAMES[*]:+ ${PROFILE_NAMES[*]}})..."
docker compose "${PROFILES[@]}" up -d --build

echo "$INFO Waiting for Logstash's pipelines to finish starting..."
# The original wait condition grepped Logstash's stdout for "Restored
# connection to ES instance" - that message only fires when Logstash
# recovers from a FAILED connection attempt. On a clean boot where
# Elasticsearch is already up before Logstash starts, it connects on the
# first try and that line never gets logged, hanging this loop forever
# (confirmed live during Phase 4 verification). Logstash's own monitoring
# API responds as soon as its pipelines have compiled and started,
# regardless of log level or connection-retry timing - a reliable signal
# instead of a message that may or may not appear.
until docker exec helk-logstash curl -s -o /dev/null http://localhost:9600; do
  sleep 5
done

# *********** Final summary ***************
KIBANA_PORT="$(grep -E '^KIBANA_PORT=' .env | cut -d= -f2)"
KIBANA_PORT="${KIBANA_PORT:-5601}"

echo ""
echo "***********************************************************************"
echo "  HELK is up"
echo "***********************************************************************"
echo "  Kibana (via Nginx, TLS):  https://localhost/"
echo "  Kibana (direct):          http://localhost:${KIBANA_PORT}/"
echo "  Login:                    user 'elastic', password = ELASTIC_PASSWORD in .env"
for p in "${PROFILE_NAMES[@]}"; do
  case "$p" in
    notebook)
      JUPYTER_TOKEN="$(grep -E '^JUPYTER_TOKEN=' .env | cut -d= -f2)"
      echo "  Spark Master UI:          http://localhost:8080/"
      echo "  Jupyter:                  https://localhost/jupyter  (token: ${JUPYTER_TOKEN})"
      ;;
    alert)
      echo "  ElastAlert2:              running (no UI; alerts land in Elasticsearch/Slack per rule config)"
      ;;
  esac
done
echo ""
echo "  Stop everything:   ./helk_remove_containers.sh ${ORIGINAL_ARGS[*]}"
echo "  Pull in updates:    ./helk_update.sh ${ORIGINAL_ARGS[*]}"
echo ""
