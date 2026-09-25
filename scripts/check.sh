#!/bin/bash
# Проверка доступности сайтов через роутер (в обход VPN на Маке — через en0).
# Использование: scripts/check.sh [iface]
IF=${1:-en0}
SITES=(
  https://www.youtube.com/
  https://i.ytimg.com/vi/jNQXAC9IVRw/maxresdefault.jpg
  https://redirector.googlevideo.com/report_mapping
  https://www.instagram.com/
  https://x.com/
  https://discord.com/
  https://rutracker.org/forum/index.php
  https://www.linkedin.com/
  https://www.google.com/
  https://ya.ru/
)
printf "%-55s %5s %9s %7s %6s\n" URL CODE BYTES TIME TLS
for u in "${SITES[@]}"; do
  r=$(curl -s -o /dev/null --interface "$IF" -m 12 -A "Mozilla/5.0" \
      -w "%{http_code} %{size_download} %{time_total} %{time_appconnect}" "$u")
  set -- $r
  printf "%-55s %5s %9s %7s %6s\n" "$u" "$1" "$2" "$3" "$4"
done
