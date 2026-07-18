#!/bin/bash

# HELK script: elastalert-entrypoint.sh
# HELK script description: Waits for Elasticsearch and the Sigma-to-ElastAlert2
# conversion pass to finish, creates the ElastAlert2 writeback index if
# missing, applies an optional Slack webhook to priority-1 curated rules, and
# starts ElastAlert2.
# License: GPL-3.0

HELK_ELASTALERT_INFO_TAG="[HELK-ELASTALERT-DOCKER-INSTALLATION-INFO]"

if [[ -z "$ES_HOST" ]]; then
  ES_HOST=helk-elasticsearch
fi
if [[ -z "$ES_PORT" ]]; then
  ES_PORT=9200
fi

if [[ -n "$ES_PASSWORD" ]]; then
    ELASTICSEARCH_ACCESS="http://${ES_USERNAME:-elastic}:${ES_PASSWORD}@${ES_HOST}:${ES_PORT}"
else
    ELASTICSEARCH_ACCESS="http://${ES_HOST}:${ES_PORT}"
fi

echo "$HELK_ELASTALERT_INFO_TAG Waiting for Elasticsearch at ${ES_HOST}:${ES_PORT}.."
until [[ "$(curl -s -o /dev/null -w "%{http_code}" "$ELASTICSEARCH_ACCESS")" == "200" ]]; do
    sleep 3
done

echo "$HELK_ELASTALERT_INFO_TAG Waiting for the Sigma-to-ElastAlert2 conversion pass to finish.."
until [[ -f "${ESALERT_HOME}/rules/sigma/.ready" ]]; do
    sleep 2
done

response_code=$(curl -s -o /dev/null -w "%{http_code}" "${ELASTICSEARCH_ACCESS}/elastalert_status")
if [[ $response_code == 404 ]]; then
    echo "$HELK_ELASTALERT_INFO_TAG Creating Elastalert index.."
    elastalert-create-index --config "${ESALERT_HOME}/config.yaml"
else
    echo "$HELK_ELASTALERT_INFO_TAG Elastalert index already exists"
fi

# *********** Setting Slack Integration on curated priority-1 rules *********
rule_counter=0
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    echo "$HELK_ELASTALERT_INFO_TAG Setting Slack webhook url to ${SLACK_WEBHOOK_URL}.."
    for er in "${ESALERT_HOME}"/rules/curated/*; do
        priority=$(sed -n -e 's/^priority: //p' "$er")
        if [[ "$priority" == "1" ]]; then
            if grep -q '^- slack$' "$er"; then
                SLACK_WEBHOOK_CURRENT=$(sed -n -e 's/^slack_webhook_url: //p' "$er")
                if [[ "$SLACK_WEBHOOK_CURRENT" == "${SLACK_WEBHOOK_URL}" ]]; then
                    echo "[+++] Slack Webhook URL provided has been already applied to rule $er"
                else
                    echo "[+++] Updating slack webhook url from $SLACK_WEBHOOK_CURRENT to $SLACK_WEBHOOK_URL"
                    sed -i "s,^slack_webhook_url\:.*$,slack_webhook_url\: ${SLACK_WEBHOOK_URL},g" "$er"
                fi
            else
                echo "[+++] Adding slack webhook url $SLACK_WEBHOOK_URL to rule $er"
                sed -i "s/^- debug$/- slack/g" "$er"
                sed -i "/- slack/a slack_webhook_url: $SLACK_WEBHOOK_URL" "$er"
            fi
            rule_counter=$((rule_counter + 1))
        fi
    done
    echo "------------------------------------------------------------------------------------"
    echo "$HELK_ELASTALERT_INFO_TAG Finished processing Slack Webhook URL info on $rule_counter curated rules"
    echo "------------------------------------------------------------------------------------"
fi

echo "$HELK_ELASTALERT_INFO_TAG Starting ElastAlert2.."
exec "$@"
