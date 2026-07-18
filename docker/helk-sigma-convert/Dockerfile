# HELK script: HELK Sigma-to-ElastAlert2 conversion Dockerfile
# HELK build Stage: Alpha
# License: GPL-3.0
#
# One-shot container: converts SigmaHQ/sigma Windows rules to ElastAlert2
# rule YAMLs at stack startup and exits. See scripts/convert_rules.py.

FROM python:3.13-slim
LABEL description="Dockerfile base for the HELK Sigma-to-ElastAlert2 rule conversion one-shot."

# Pinned release tag, not a moving branch - re-pin deliberately, don't let
# this float across restarts of the same deployment.
ARG SIGMA_RULES_REF=r2026-07-01

RUN apt-get update -qq && apt-get install -qqy --no-install-recommends \
  git \
  ca-certificates \
  && apt-get -qy clean autoremove \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir sigma-cli==3.1.0 pysigma-backend-elasticsearch==2.1.0 \
  && git clone --depth 1 --branch "${SIGMA_RULES_REF}" https://github.com/SigmaHQ/sigma.git /opt/sigma-rules-src \
  && mkdir -p /opt/sigma-rules \
  && mv /opt/sigma-rules-src/rules/windows /opt/sigma-rules/windows \
  && rm -rf /opt/sigma-rules-src

WORKDIR /opt/helk-sigma-convert
COPY pipeline ./pipeline
COPY scripts/convert_rules.py scripts/sigma-convert-entrypoint.sh ./scripts/
RUN chmod +x ./scripts/sigma-convert-entrypoint.sh

ENTRYPOINT ["./scripts/sigma-convert-entrypoint.sh"]
