#!/bin/bash

# HELK script: helk_remove_containers.sh
# HELK script description: Tear down the HELK stack
# HELK build Stage: Alpha
# License: GPL-3.0

# Phase 4 rewrite: the old version asked the user to type back one of four
# legacy 'helk-kibana-*-basic.yml' filenames (none of which exist anymore -
# there is one compose.yaml with profiles) and force-removed any local image
# matching a broad grep across otrf/cyb3rward0g/helk/logstash/kibana/
# elasticsearch/cp-ksql - a pattern that could just as easily match an
# unrelated image on the same Docker host. This version just wraps
# `docker compose down` scoped to this project, and only touches volumes or
# images when explicitly asked. See MODERNIZATION.md Phase 4 / §5 decision #4.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INFO="[HELK-REMOVE]"
ERR="[HELK-REMOVE-ERROR]"

usage() {
  cat <<EOF
Usage: $0 [--profile alert] [--profile notebook] [--volumes] [--images] [-y|--yes] [-h|--help]

Stops and removes the HELK containers via 'docker compose down'. Pass the
same --profile flags you used with helk_install.sh so those services are
included in the teardown (docker compose only tears down profile-gated
services when the same profile is passed to the command).

  --volumes   also delete this project's named volumes (Elasticsearch data,
              Kafka data, Hive metastore, etc) - DESTRUCTIVE, cannot be undone
  --images    also delete every image used by this project's services
              (docker compose --rmi all) - both locally built images and
              plain pulled ones (e.g. the Elasticsearch setup image), all
              re-buildable/re-pullable; does not touch unrelated images on
              this host
  -y, --yes   don't prompt for confirmation before a destructive action
EOF
  exit 1
}

PROFILES=()
REMOVE_VOLUMES=""
REMOVE_IMAGES=""
ASSUME_YES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || usage
      PROFILES+=(--profile "$2")
      shift 2
      ;;
    --volumes) REMOVE_VOLUMES="1"; shift ;;
    --images) REMOVE_IMAGES="1"; shift ;;
    -y|--yes) ASSUME_YES="1"; shift ;;
    -h|--help) usage ;;
    *)
      echo "$ERR Unknown option: $1"
      usage
      ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "$ERR docker was not found on PATH."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "$ERR 'docker compose' (the Compose v2 plugin) is not available."; exit 1; }

if [[ ! -f compose.yaml ]]; then
  echo "$ERR compose.yaml not found in $SCRIPT_DIR - this script must live in the same directory as compose.yaml."
  exit 1
fi

DOWN_ARGS=()
if [[ -n "$REMOVE_VOLUMES" ]]; then
  DOWN_ARGS+=(-v)
fi
if [[ -n "$REMOVE_IMAGES" ]]; then
  # `--rmi local` only removes images that DON'T have a custom `image:` tag -
  # every service in compose.yaml sets one, so `local` would silently remove
  # nothing. `all` removes every image (built or pulled) used by a service.
  DOWN_ARGS+=(--rmi all)
fi

if [[ -n "$REMOVE_VOLUMES" && -z "$ASSUME_YES" ]]; then
  echo "$INFO --volumes will permanently delete this project's named volumes, including:"
  echo "    Elasticsearch data (esdata), Kafka data (kafkadata), Nginx TLS certs,"
  echo "    the ElastAlert/Sigma rules cache, and the Jupyter Hive metastore."
  read -r -p "Continue? (y/n) " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "$INFO Aborted - nothing changed."; exit 1; }
fi

if [[ -n "$REMOVE_IMAGES" && -z "$ASSUME_YES" ]]; then
  echo "$INFO --images will delete every image this stack's services use (built and pulled) - the next install will need to rebuild/re-pull all of them."
  read -r -p "Continue? (y/n) " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "$INFO Aborted - nothing changed."; exit 1; }
fi

echo "$INFO Stopping and removing HELK containers${REMOVE_VOLUMES:+ and volumes}${REMOVE_IMAGES:+ and locally built images}..."
docker compose "${PROFILES[@]}" down "${DOWN_ARGS[@]}"

echo "$INFO Done."
