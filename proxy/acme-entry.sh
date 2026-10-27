#!/bin/sh
set -eu

if [ "${PROXY_CERT_MODE:-own}" != "letsencrypt" ]; then
  echo "PROXY_CERT_MODE=${PROXY_CERT_MODE:-own}: own certificate, not requesting one from Let's Encrypt."
  exec sleep infinity
fi

if [ -z "${ACME_EMAIL:-}" ]; then
  echo "ACME_EMAIL is required for Let's Encrypt." >&2
  exit 1
fi

host_of() {
  h=$1
  h=${h#*://}
  h=${h%%/*}
  h=${h%%:*}
  printf '%s' "$h"
}

WEB=$(host_of "${WEB_PUBLIC_URL:?WEB_PUBLIC_URL is required}")
API=$(host_of "${API_PUBLIC_URL:?API_PUBLIC_URL is required}")
PUSH=$(host_of "${SIGNALR_PUBLIC_URL:?SIGNALR_PUBLIC_URL is required}")

mkdir -p /acme.sh /var/www/acme /certs

acme() {
  acme.sh --home /acmebin --config-home /acme.sh "$@"
}

acme --register-account -m "$ACME_EMAIL" --server letsencrypt || true

i=0
while true; do
  set +e
  acme --issue --server letsencrypt -w /var/www/acme \
    -d "$WEB" -d "$API" -d "$PUSH"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
    break
  fi
  i=$((i + 1))
  if [ "$i" -ge 6 ]; then
    echo "Let's Encrypt did not issue a certificate." >&2
    exit 1
  fi
  echo "Issue failed (exit $rc). Retry $i in 15 seconds." >&2
  sleep 15
done

acme --install-cert -d "$WEB" \
  --fullchain-file /certs/fullchain.pem \
  --key-file /certs/privkey.pem \
  --reloadcmd "true"

# Certificate is about 90 days. The image scheduler runs acme.sh --cron
# several times a day and asks for a new one about a month before it ends.
# install-cert above saved the file paths, so renewal writes the same two files.
echo "Certificate installed. Renewal stays running."
exec /entry.sh daemon
