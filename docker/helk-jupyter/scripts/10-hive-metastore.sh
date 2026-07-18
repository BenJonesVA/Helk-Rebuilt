#!/bin/bash

# Notebooks Forge script: 10-hive-metastore.sh
# Notebooks Forge script description: Starts Postgres and provisions the Hive
# metastore database before-notebook.d (docker-stacks startup hook)
# Notebooks Forge build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0
# Reference: https://blog.ouseful.info/2019/02/04/running-a-postgresql-server-in-a-mybinder-container/

# NOTE: docker-stacks' start.sh sources before-notebook.d/*.sh scripts into
# its own shell rather than executing them as subprocesses - `set -e` here
# would propagate to start.sh itself and silently kill the whole container on
# any failure in this script, so deliberately not using it.

NOTEBOOK_INFO_TAG="[NOTEBOOK-JUPYTER-DOCKER-INSTALLATION-INFO]"

# postgresql-contrib installs whatever major version ships with the base
# image's Ubuntu release (not the "10" the original image pinned) - detect it
# rather than hardcoding a version that will drift out from under this script.
# Binaries live at /usr/lib/postgresql/<version>/bin/initdb, i.e. 3 levels
# down from /usr/lib/postgresql.
PG_BINDIR=$(dirname "$(find /usr/lib/postgresql -maxdepth 3 -name initdb | sort -V | tail -n1)")
HIVE_METASTORE_PASSWORD=${HIVE_METASTORE_PASSWORD:-sparkpassword}

# ************ Starting Postgresql for Spark ****************
# PGDATA is a mounted volume (for persistence across container recreation),
# so the directory itself always exists even when empty - check for a file
# initdb actually creates, not just directory presence.
PGDATA=${PGDATA:-${HOME}/srv/pgsql}

if [ ! -f "$PGDATA/PG_VERSION" ]; then
  "${PG_BINDIR}/initdb" -D "$PGDATA" --auth-host=md5 --encoding=UTF8
fi
echo "$NOTEBOOK_INFO_TAG The files in this database system will be owned by user ${NB_USER:-jovyan}.."
"${PG_BINDIR}/pg_ctl" -D "$PGDATA" status || "${PG_BINDIR}/pg_ctl" -D "$PGDATA" -l "$PGDATA/pg.log" start

# ************ Checking if user hive exists ****************
echo "$NOTEBOOK_INFO_TAG Checking if user hive already exists.."
HIVE_USER_EXISTS=$(psql postgres -tAc "SELECT 1 FROM pg_catalog.pg_user u WHERE u.usename='hive'")
if [[ $HIVE_USER_EXISTS != "1" ]]; then
    echo "$NOTEBOOK_INFO_TAG postgres user hive does not exist.."
    psql postgres --command "CREATE USER hive;"
    psql postgres --command "ALTER ROLE hive WITH PASSWORD '${HIVE_METASTORE_PASSWORD}';"
    psql postgres --command "CREATE DATABASE hive_metastore;"
    psql postgres --command "GRANT ALL PRIVILEGES ON DATABASE hive_metastore TO hive;"
elif [[ $HIVE_USER_EXISTS == "1" ]]; then
    echo "$NOTEBOOK_INFO_TAG postgres hive user already exists.."
fi
