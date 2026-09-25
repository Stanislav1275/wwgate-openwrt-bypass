#!/bin/bash
# Бэкап конфигурации роутера: backups/<дата>/
cd "$(dirname "$0")/.."
D=backups/$(date +%Y-%m-%d_%H%M)
mkdir -p "$D"
bin/r 'sysupgrade -b - 2>/dev/null' > "$D/config-backup.tar.gz"
bin/r 'apk list -I' > "$D/packages.txt"
bin/r 'uci export zapret2' > "$D/zapret.uci"
bin/r 'cat /opt/zapret2/ipset/zapret-hosts-auto.txt /opt/zapret2/ipset/zapret-hosts-user.txt' > "$D/zapret-hosts.txt"
ls -la "$D"
