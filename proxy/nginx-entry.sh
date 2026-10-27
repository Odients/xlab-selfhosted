#!/bin/sh
set -eu

host_of() {
  h=$1
  h=${h#*://}
  h=${h%%/*}
  h=${h%%:*}
  printf '%s' "$h"
}

export WEB_HOST=$(host_of "${WEB_PUBLIC_URL:?WEB_PUBLIC_URL is required}")
export API_HOST=$(host_of "${API_PUBLIC_URL:?API_PUBLIC_URL is required}")
export SIGNALR_HOST=$(host_of "${SIGNALR_PUBLIC_URL:?SIGNALR_PUBLIC_URL is required}")
export NGINX_ENVSUBST_FILTER='^(WEB_HOST|API_HOST|SIGNALR_HOST)$'

mkdir -p /certs /var/www/acme

if [ ! -s /certs/fullchain.pem ] || [ ! -s /certs/privkey.pem ]; then
  echo "No fullchain.pem and privkey.pem in /certs. Creating a 2-day self-signed certificate so nginx can start."
  apk add --no-cache openssl >/dev/null
  openssl req -x509 -newkey rsa:2048 -sha256 -days 2 -nodes \
    -keyout /certs/privkey.pem \
    -out /certs/fullchain.pem \
    -subj "/CN=${WEB_HOST}" \
    -addext "subjectAltName=DNS:${WEB_HOST},DNS:${API_HOST},DNS:${SIGNALR_HOST}"
fi

/docker-entrypoint.sh nginx -g 'daemon off;' &
nginx_pid=$!

term() {
  kill "$nginx_pid" 2>/dev/null || true
  wait "$nginx_pid" 2>/dev/null || true
  exit 0
}
trap term TERM INT

last=$(stat -c %Y /certs/fullchain.pem 2>/dev/null || echo 0)
while kill -0 "$nginx_pid" 2>/dev/null; do
  sleep 5 &
  wait $! || true
  now=$(stat -c %Y /certs/fullchain.pem 2>/dev/null || echo 0)
  if [ "$now" != "$last" ]; then
    nginx -s reload || true
    last=$now
  fi
done
wait "$nginx_pid"
