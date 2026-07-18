# HELK script: HELK Jupyter Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

# Base carries Spark 4.1.2 (Scala 2.13) + Java 21 + a pinned conda Python
# already wired up for PySpark - helk-spark-master/worker are built from this
# exact same image tag so the driver and executors always match. See
# MODERNIZATION.md Phase 3 for why (PySpark requires driver/executor Python
# version parity) and for the graphframes.io citation on the two-jar install.
FROM quay.io/jupyter/pyspark-notebook:spark-4.1.2
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile Notebooks-Forge Jupyter-Hunt Project."

USER root

# *********** Setting Environment Variables ***************
ENV POSTGRESQL_JDBC_VERSION=42.7.13
ENV GRAPHFRAMES_VERSION=0.12.1
# Elastic has not published a Spark 4-targeted build of this connector (its
# newest artifact, elasticsearch-spark-30_2.13, is only documented against
# Spark 3.0-3.4) - included on a best-effort basis for the read_elasticsearch
# demo notebooks; verify empirically, don't assume it works. See
# MODERNIZATION.md Phase 3.
ENV ES_SPARK_CONNECTOR_VERSION=9.0.3

# ********** Installing additional libraries **************
# postgresql/postgresql-contrib: local Hive metastore backing store (carried
# over from the original image - table definitions must survive notebook
# restarts, and the new upstream base doesn't provide this on its own).
RUN mkdir -p ${HOME}/notebooks/datasets \
    && apt-get update --fix-missing && apt-get install -y --no-install-recommends \
    postgresql postgresql-contrib \
    # ********** Clean APT **********
    && apt-get -qy clean autoremove \
    && rm -rf /var/lib/apt/lists/* \
    # apt's postgresql package owns this socket dir by the "postgres" system
    # user; Postgres runs as jovyan here (via before-notebook.d), so it needs
    # ownership to create its connection lock file.
    && chown ${NB_UID}:${NB_GID} /var/run/postgresql \
    # ********** Download Postgresql JDBC + GraphFrames JARs *****************
    && wget -q "https://jdbc.postgresql.org/download/postgresql-${POSTGRESQL_JDBC_VERSION}.jar" -P "${SPARK_HOME}/jars/" \
    && wget -q "https://repo1.maven.org/maven2/io/graphframes/graphframes-spark4_2.13/${GRAPHFRAMES_VERSION}/graphframes-spark4_2.13-${GRAPHFRAMES_VERSION}.jar" -P "${SPARK_HOME}/jars/" \
    && wget -q "https://repo1.maven.org/maven2/io/graphframes/graphframes-graphx-spark4_2.13/${GRAPHFRAMES_VERSION}/graphframes-graphx-spark4_2.13-${GRAPHFRAMES_VERSION}.jar" -P "${SPARK_HOME}/jars/" \
    && wget -q "https://repo1.maven.org/maven2/org/elasticsearch/elasticsearch-spark-30_2.13/${ES_SPARK_CONNECTOR_VERSION}/elasticsearch-spark-30_2.13-${ES_SPARK_CONNECTOR_VERSION}.jar" -P "${SPARK_HOME}/jars/"

RUN pip install --no-cache-dir "graphframes-py==${GRAPHFRAMES_VERSION}"

# All 378 Sigma-derived notebooks (notebooks/sigma/) query Elasticsearch
# directly via `elasticsearch`/`elasticsearch_dsl`, not PySpark - neither
# package exists anywhere in this base image, so none of the 378 can even
# import their dependencies as shipped. elasticsearch-dsl's last standalone
# release (8.18.0) pins elasticsearch<9, so the client here is one major
# behind the 9.4.3 server - within Elastic's documented N-1 client/server
# compatibility window, not a mismatch. See MODERNIZATION.md Phase 3 for the
# remaining API-level breaks (the ES(['url']) constructor, doc_type=, and
# missing auth) that are NOT fixed here and affect all 378 notebooks, not
# just a few.
RUN pip install --no-cache-dir elasticsearch==8.18.1 elasticsearch-dsl==8.18.0

# The base image installs Spark's JVM side but does not put PySpark on
# PYTHONPATH or pip-install a separate `pyspark` package - `import pyspark`
# fails out of the box despite the image's name. Use the bundled
# $SPARK_HOME/python (guarantees an exact version match with the driver's own
# Spark install, avoiding a second, potentially mismatched `pip install
# pyspark`) - symlink the version-numbered py4j zip to a stable name so this
# doesn't need updating if the base image bumps its bundled py4j version.
RUN ln -s "$(ls ${SPARK_HOME}/python/lib/py4j-*-src.zip)" "${SPARK_HOME}/python/lib/py4j-src.zip"
ENV PYTHONPATH="${SPARK_HOME}/python:${SPARK_HOME}/python/lib/py4j-src.zip"

# *********** Adding HELK scripts and files to Container ***************
COPY notebooks/demos ${HOME}/notebooks/demos
COPY notebooks/tutorials ${HOME}/notebooks/tutorials
COPY notebooks/sigma ${HOME}/notebooks/sigma
COPY spark/* ${SPARK_HOME}/conf/
# docker-stacks hook: anything executable dropped in before-notebook.d/ runs
# before the notebook server starts. Keeps our Postgres/Hive-metastore setup
# on the base image's own tini+start.sh init path instead of replacing it.
COPY scripts/10-hive-metastore.sh /usr/local/bin/before-notebook.d/10-hive-metastore.sh

RUN chmod +x /usr/local/bin/before-notebook.d/10-hive-metastore.sh \
    && fix-permissions "${HOME}" "${SPARK_HOME}/conf"

# Pre-create PGDATA's mountpoint with jovyan ownership: Docker seeds a fresh
# named volume's initial content (including ownership) from whatever already
# exists at that path in the image, and initdb needs to own its own data
# directory (it chmods 0700 on first run, which fails as a non-owner).
RUN mkdir -p "${HOME}/srv/pgsql" && chown ${NB_UID}:${NB_GID} "${HOME}/srv/pgsql"

WORKDIR ${HOME}
CMD ["start-notebook.py", "--ServerApp.base_url=/jupyter"]

USER ${NB_UID}
