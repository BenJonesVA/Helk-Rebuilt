# HELK script: HELK ElastAlert2 Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

FROM python:3.13-slim
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile base for the HELK ElastAlert2."

ENV ESALERT_GID=910
ENV ESALERT_UID=910
ENV ESALERT_USER=elastalertuser
ENV ESALERT_HOME=/etc/elastalert

# elastalert2 officially supports pointing its (pinned, ES7-client) library at
# ES8/ES9 clusters - see MODERNIZATION.md - so no version-compat workaround is
# needed here, unlike the old elasticsearch==7.0.0 pin this replaces.
RUN apt-get update -qq && apt-get install -qqy --no-install-recommends \
  curl \
  && apt-get -qy clean autoremove \
  && rm -rf /var/lib/apt/lists/* \
  && pip install --no-cache-dir elastalert2==2.30.0 \
  && mkdir -p ${ESALERT_HOME}/rules/curated ${ESALERT_HOME}/rules/sigma

COPY scripts/* ${ESALERT_HOME}/
COPY config.yaml ${ESALERT_HOME}/
COPY rules/* ${ESALERT_HOME}/rules/curated/

RUN chmod +x ${ESALERT_HOME}/elastalert-entrypoint.sh \
  && groupadd -g ${ESALERT_GID} ${ESALERT_USER} \
  && useradd -u ${ESALERT_UID} -g ${ESALERT_GID} -d ${ESALERT_HOME} --no-create-home -s /bin/bash ${ESALERT_USER} \
  && chown -R ${ESALERT_USER}:${ESALERT_USER} ${ESALERT_HOME}

USER elastalertuser
WORKDIR ${ESALERT_HOME}
ENTRYPOINT ["./elastalert-entrypoint.sh"]
CMD ["elastalert", "--verbose"]
