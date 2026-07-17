# HELK script: HELK Logstash Dockerfile
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

# References:
# https://cyberwardog.blogspot.com/2017/02/setting-up-pentesting-i-mean-threat_98.html

FROM docker.elastic.co/logstash/logstash:9.4.3
LABEL maintainer="Roberto Rodriguez @Cyb3rWard0g"
LABEL description="Dockerfile base for the HELK Logstash."

COPY --chown=logstash:logstash config /usr/share/logstash/config

# logstash-codec-cef and logstash-codec-netflow are the only two plugins HELK's pipeline
# needs that aren't part of Logstash's default bundle — everything else it used to vendor
# offline (beats input, ES output, kafka integration, etc.) ships by default already.
RUN logstash-plugin install logstash-codec-cef logstash-codec-netflow \
    && rm -f /usr/share/logstash/pipeline/logstash.conf
