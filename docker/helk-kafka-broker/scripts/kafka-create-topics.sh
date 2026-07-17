#!/bin/bash

# HELK script: kafka-create-topics.sh
# HELK script description: creates kafka topics
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

if [[ -z "$KAFKA_BOOTSTRAP_SERVER" ]]; then
  KAFKA_BOOTSTRAP_SERVER=helk-kafka-broker:9092
fi

if [[ -z "$REPLICATION_FACTOR" ]]; then
  REPLICATION_FACTOR=1
fi

if [[ -z "$KAFKA_CREATE_TOPICS" ]]; then
  KAFKA_CREATE_TOPICS=winlogbeat
fi

# *********** Waiting for Kafka broker to be up ***************
echo "[HELK-DOCKER-INSTALLATION-INFO] Checking to see if Kafka broker is up..."
until /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" >/dev/null 2>&1; do
  echo "[HELK-DOCKER-INSTALLATION-INFO] Kafka broker ${KAFKA_BOOTSTRAP_SERVER} is not available yet"
  sleep 2
done

# *********** Creating Kafka Topics **************
# Reference: https://stackoverflow.com/questions/10586153/split-string-into-an-array-in-bash
IFS=', ' read -r -a temas <<< "$KAFKA_CREATE_TOPICS"

for t in "${temas[@]}"; do
  echo "[HELK-DOCKER-INSTALLATION-INFO] Creating Kafka ${t} Topic.."
  /opt/kafka/bin/kafka-topics.sh --create --bootstrap-server "${KAFKA_BOOTSTRAP_SERVER}" --replication-factor "${REPLICATION_FACTOR}" --partitions 1 --topic "${t}" --if-not-exists
done
