#!/bin/bash
# Применить стратегию zapret2 (config/zapret2.NFQWS2_OPT.txt или $1) и hostlist на роутер.
cd "$(dirname "$0")/.."
OPT=$(cat "${1:-config/zapret2.NFQWS2_OPT.txt}")
bin/r 'cat > /opt/zapret2/ipset/zapret-hosts-user.txt' < config/zapret2-hosts-user.txt
printf '%s' "$OPT" | bin/r 'uci set zapret2.config.NFQWS2_OPT="
$(cat)
"; uci commit zapret2; /opt/zapret2/sync_config.sh; /etc/init.d/zapret2 restart >/dev/null 2>&1; sleep 2; pidof nfqws2 >/dev/null && echo "zapret2: running" || echo "zapret2: FAILED"'
