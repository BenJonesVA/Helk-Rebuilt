#!/bin/bash

# HELK script: sigma-convert-entrypoint.sh
# HELK script description: One-shot conversion of SigmaHQ/sigma Windows rules
# into ElastAlert2 rule YAMLs, written to a volume shared with helk-elastalert.
# License: GPL-3.0

HELK_INFO_TAG="[HELK-SIGMA-CONVERT-DOCKER-INSTALLATION-INFO]"

echo "$HELK_INFO_TAG Clearing stale converted rules from a previous run.."
find "${SIGMA_OUTPUT_DIR:-/output}" -maxdepth 1 -name 'Sigma_*.yaml' -delete
rm -f "${SIGMA_OUTPUT_DIR:-/output}/.ready"

echo "$HELK_INFO_TAG Converting SigmaHQ/sigma Windows rules to ElastAlert2 rules.."
python3 /opt/helk-sigma-convert/scripts/convert_rules.py

echo "$HELK_INFO_TAG Done."
