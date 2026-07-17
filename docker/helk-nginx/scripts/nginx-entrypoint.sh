#!/bin/sh

# HELK script: nginx-entrypoint.sh
# HELK script description: Runs Nginx service
# HELK build Stage: Alpha
# Author: Roberto Rodriguez (@Cyb3rWard0g)
# License: GPL-3.0

until curl -s helk-elasticsearch:9200 -o /dev/null; do
    sleep 1
done

# ************* Creating TLS certificate (once — persisted in a volume) ***********
if [ ! -f /etc/ssl/certs/HELK_Nginx.crt ] || [ ! -f /etc/ssl/private/HELK_Nginx.key ]; then
    echo "[HELK-DOCKER-INSTALLATION-INFO] Generating self-signed TLS certificate.."
    openssl req \
        -x509 \
        -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/ssl/private/HELK_Nginx.key \
        -out /etc/ssl/certs/HELK_Nginx.crt \
        -subj "/C=US/ST=VA/L=VA/O=HELK/OU=HELK Nginx/CN=HELK"
else
    echo "[HELK-DOCKER-INSTALLATION-INFO] Reusing existing TLS certificate.."
fi

echo "[HELK-DOCKER-INSTALLATION-INFO] Starting nginx.."
exec nginx -g "daemon off;"
