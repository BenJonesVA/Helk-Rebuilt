#!/bin/bash

# HELK script: helk_update.sh
# HELK script description: Pull latest changes and rebuild the HELK stack
# HELK build Stage: Alpha
# License: GPL-3.0

# Phase 4 rewrite: the old version silently ran `git clean -d -fx .` (deletes
# every untracked file with no confirmation) as part of a routine update, and
# read a hardcoded `../.git/refs/heads/master` for logging - broken on this
# repo (branch is `main`, not `master`) and on any shallow clone. It also
# added a remote pointing at the original upstream repo
# (Cyb3rWard0g/HELK.git), which is wrong for a fork. This version never
# deletes anything without an explicit, itemized confirmation, always reads
# the branch/remote dynamically, and pulls from `origin` (whatever the clone
# is actually configured to track). See MODERNIZATION.md Phase 4 / §5
# decision #4.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INFO="[HELK-UPDATE]"
ERR="[HELK-UPDATE-ERROR]"

usage() {
  cat <<EOF
Usage: $0 [--profile alert] [--profile notebook] [-y|--yes] [-h|--help]

Pulls the latest commits for the current branch from 'origin', then rebuilds
and restarts the HELK stack via 'docker compose'. Pass the same --profile
flags you used with helk_install.sh so the right optional components get
rebuilt too.

  -y, --yes   don't prompt for confirmation before rebuilding
EOF
  exit 1
}

PROFILES=()
PROFILE_NAMES=()
ASSUME_YES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || usage
      PROFILES+=(--profile "$2")
      PROFILE_NAMES+=("$2")
      shift 2
      ;;
    -y|--yes) ASSUME_YES="1"; shift ;;
    -h|--help) usage ;;
    *)
      echo "$ERR Unknown option: $1"
      usage
      ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "$ERR git was not found on PATH."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "$ERR docker was not found on PATH."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "$ERR 'docker compose' (the Compose v2 plugin) is not available."; exit 1; }

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$ERR This doesn't look like a git checkout - can't determine what to update. Cannot continue."
  exit 1
}
cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "HEAD" ]]; then
  echo "$ERR Repo is in a detached HEAD state, not on a branch. Check out a branch first (e.g. 'git checkout main')."
  exit 1
fi

REMOTE="$(git config "branch.${BRANCH}.remote" || echo origin)"
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "$ERR Remote '$REMOTE' is not configured. Cannot continue."
  exit 1
fi

# *********** Never silently discard local work ***************
if [[ -n "$(git status --porcelain)" ]]; then
  echo "$ERR You have uncommitted changes or untracked files:"
  git status --short | sed 's/^/    /'
  echo "$ERR Commit, stash, or remove them yourself first (this script will not touch them), then re-run."
  exit 1
fi

echo "$INFO Fetching '$REMOTE'..."
git fetch "$REMOTE" "$BRANCH"

LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "$REMOTE/$BRANCH")"

if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]]; then
  echo "$INFO Already up to date ($BRANCH @ ${LOCAL_HEAD:0:12})."
  exit 0
fi

echo "$INFO Updates available: ${LOCAL_HEAD:0:12} -> ${REMOTE_HEAD:0:12}"
git log --oneline "${LOCAL_HEAD}..${REMOTE_HEAD}" | sed 's/^/    /'

if [[ -z "$ASSUME_YES" ]]; then
  read -r -p "Pull these changes and rebuild HELK now? (y/n) " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "$INFO Aborted - nothing changed."; exit 1; }
fi

echo "$INFO Pulling (fast-forward only)..."
if ! git pull --ff-only "$REMOTE" "$BRANCH"; then
  echo "$ERR Fast-forward pull failed - your branch has diverged from '$REMOTE/$BRANCH'. Resolve this manually with git (rebase/merge), then re-run."
  exit 1
fi

cd "$SCRIPT_DIR"

echo "$INFO Rebuilding and restarting HELK (profiles:${PROFILE_NAMES[*]:+ ${PROFILE_NAMES[*]}})..."
docker compose "${PROFILES[@]}" up -d --build --remove-orphans

echo "$INFO Waiting for Logstash's pipelines to finish starting..."
# See the matching comment in helk_install.sh: grepping stdout for "Restored
# connection to ES instance" only fires on a reconnect after a failed
# attempt, so it hangs forever whenever Elasticsearch is already up before
# Logstash starts (confirmed live). Logstash's own monitoring API is a
# reliable signal instead.
until docker exec helk-logstash curl -s -o /dev/null http://localhost:9600; do
  sleep 5
done

echo "$INFO HELK updated and running at $(git rev-parse --short HEAD)."
