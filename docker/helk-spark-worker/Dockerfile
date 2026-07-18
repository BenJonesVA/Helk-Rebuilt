# HELK script: HELK Spark Worker Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

# Built from the same image tag as helk-jupyter (the Spark driver) rather than
# a generic Spark image + hand-installed Miniconda (the old approach here) -
# this base already ships the exact Python build the driver uses, which is
# what PySpark's driver/executor version match actually requires. See
# MODERNIZATION.md Phase 3 for the reasoning.
FROM quay.io/jupyter/pyspark-notebook:spark-4.1.2
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile base for HELK Spark Worker."

USER root
COPY scripts/spark-worker-entrypoint.sh ${SPARK_HOME}/sbin/
COPY spark-defaults.conf ${SPARK_HOME}/conf/
RUN chmod +x ${SPARK_HOME}/sbin/spark-worker-entrypoint.sh \
    && mkdir -p ${SPARK_HOME}/work ${SPARK_HOME}/logs \
    && chown -R ${NB_UID}:${NB_GID} ${SPARK_HOME}/work ${SPARK_HOME}/logs

# Executors launch a `python3 -m pyspark.worker` subprocess for Python
# UDF/RDD tasks - it needs the same PySpark-on-PYTHONPATH fix as the driver
# (helk-jupyter), for the same reason (the base image doesn't put PySpark on
# PYTHONPATH or pip-install it despite its name).
RUN ln -s "$(ls ${SPARK_HOME}/python/lib/py4j-*-src.zip)" "${SPARK_HOME}/python/lib/py4j-src.zip"
ENV PYTHONPATH="${SPARK_HOME}/python:${SPARK_HOME}/python/lib/py4j-src.zip"

# The base image's own healthcheck probes Jupyter's HTTP endpoint, which this
# service never runs - inheriting it would leave the container permanently
# "unhealthy" even when the Spark Worker is fine.
HEALTHCHECK NONE

WORKDIR $SPARK_HOME/sbin
USER ${NB_UID}
ENTRYPOINT ["./spark-worker-entrypoint.sh"]