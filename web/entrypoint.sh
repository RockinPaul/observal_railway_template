#!/bin/sh
# Render the nginx config with Railway's DNS resolver, fix the UI's websocket URL, then start nginx.
set -eu
: "${PORT:=3000}"
: "${API_UPSTREAM:=http://api.railway.internal:8000}"

# nginx needs an explicit resolver for variable upstreams; take the container's.
ns="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)"
case "$ns" in *:*) ns="[$ns]" ;; esac
sed -e "s|__RESOLVER__|$ns|" -e "s|__PORT__|$PORT|g" -e "s|__API_UPSTREAM__|$API_UPSTREAM|" \
  /etc/nginx/templates/observal.conf.in > /etc/nginx/conf.d/default.conf

# Upstream's build opens GraphQL subscriptions on <hostname>:8000 unless VITE_API_URL was set at
# build time. Point it at the page's own origin so /api/v1/graphql goes through this proxy.
f="$(grep -l 'window.location.hostname}:8000' /usr/share/nginx/html/assets/graphql-ws-*.js | head -1)"
if [ -n "$f" ]; then
  sed -i 's/${window.location.hostname}:8000/${window.location.host}/' "$f"
  echo "patched websocket origin in $(basename "$f")"
elif grep -q 'window.location.host}`' /usr/share/nginx/html/assets/graphql-ws-*.js; then
  echo "websocket origin already patched"
else
  echo "websocket patch target not found in the bundle; refusing to serve a UI whose live updates would fail" >&2; exit 1
fi

exec "$@"
