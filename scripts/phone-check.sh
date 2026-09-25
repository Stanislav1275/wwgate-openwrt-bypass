#!/bin/bash
# Проверка сайтов с Android-телефона (adb) через Wi-Fi роутера.
# DNS резолвим на роутере, curl на телефоне (/data/local/tmp/curl) — через wlan0.
cd "$(dirname "$0")/.."
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
DEV=${DEV:-192.168.2.180:40431}
HOSTS="www.youtube.com youtubei.googleapis.com redirector.googlevideo.com i.ytimg.com www.instagram.com x.com discord.com rutracker.org www.linkedin.com www.google.com ya.ru"
ARGS=""
for h in $HOSTS; do
  ip=$(bin/r "nslookup $h 127.0.0.1 2>/dev/null | awk '/^Address/ && \$2 ~ /^[0-9.]+\$/ && \$2 != \"127.0.0.1\" {print \$2; exit}'")
  ARGS="$ARGS $h:$ip"
done
$ADB -s $DEV shell "cd /data/local/tmp; for hi in $ARGS; do h=\${hi%%:*}; ip=\${hi#*:}; \
  r=\$(./curl -sk -o /dev/null -m 8 --interface wlan0 -A Mozilla/5.0 --resolve \$h:443:\$ip -w '%{http_code} %{size_download} %{time_total}' https://\$h/); \
  echo \"\$r \$h\"; done"
