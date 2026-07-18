# HELK script: HELK Spark Master Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

# Built from the same image tag as helk-jupyter (the Spark driver) rather than
# a generic Spark image - PySpark requires the driver and executors to run
# matching Python major.minor versions, and this is the only way to guarantee
# that without hand-pinning a Python build to track the Jupyter image's conda
# Python across upgrades. See MODERNIZATION.md Phase 3 for the reasoning.
FROM quay.io/jupyter/pyspark-notebook:spark-4.1.2
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile base for HELK Spark Master."

USER root
COPY scripts/spark-master-entrypoint.sh ${SPARK_HOME}/sbin/
COPY spark-defaults.conf ${SPARK_HOME}/conf/
RUN chmod +x ${SPARK_HOME}/sbin/spark-master-entrypoint.sh \
    && mkdir -p ${SPARK_HOME}/work ${SPARK_HOME}/logs \
    && chown -R ${NB_UID}:${NB_GID} ${SPARK_HOME}/work ${SPARK_HOME}/logs

# The base image's own healthcheck probes Jupyter's HTTP endpoint, which this
# service never runs - inheriting it would leave the container permanently
# "unhealthy" even when Spark Master is fine.
HEALTHCHECK NONE

EXPOSE 8080 7077
WORKDIR $SPARK_HOME/sbin
USER ${NB_UID}
ENTRYPOINT ["./spark-master-entrypoint.sh"]