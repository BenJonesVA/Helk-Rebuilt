# HELK script: HELK Kafka Broker Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

FROM apache/kafka:4.3.1
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile base for the HELK Kafka Broker."

# Configuration is env-var driven (KAFKA_* mapped by the base image's own entrypoint) —
# see compose.yaml. Topic creation is handled by a separate one-shot setup container.
