# wwGate AX3000 — OpenWrt-роутер для обхода блокировок

Домашний роутер, который прозрачно (без настроек на устройствах) открывает для всех клиентов Wi‑Fi:

- сайты, заблокированные в РФ по DPI (YouTube, Discord, X, rutracker, LinkedIn, ~460 сайтов из реестра) — через **zapret2**;
- сайты, заблокированные по IP (Telegram), звонки WhatsApp и сервисы, которые сами не пускают из РФ
  (ChatGPT, Claude, Gemini, Spotify, Notion…) — через **VLESS** (podkop + sing-box).

Для ИИ-агентов: краткая справка и правила — в [`CLAUDE.md`](CLAUDE.md). Подробное руководство по подбору
стратегий — раздел [«Подбор стратегий»](#подбор-стратегий-руководство-для-claude--другого-агента) ниже.

---

## 1. Схема

```
Интернет ─ Ростелеком RT-GPON-XXXX (192.168.1.1)
              │ LAN ──кабель── WAN
              ▼
         wwGate AX3000  (WAN 192.168.1.23 по DHCP, LAN 192.168.2.1/24)
              ├─ Wi‑Fi wwGate-2.4G  (WPA2)
              ├─ Wi‑Fi wwGate-5G    (WPA2)
              └─ LAN1-3

Клиент ─► dnsmasq ─► sing-box DNS (fakeip 198.18.0.0/15 для доменов из списков) ─► 77.88.8.8
Клиент ─► [podkop/sing-box]
             ├─ исключение yt_direct (YouTube + config/zapret-ok-domains.lst) ─► WAN ─► zapret2 (DPI-обход)
             ├─ main: russia_inside, google_ai, telegram, meta, discord, twitter ─► VLESS (Франкфурт, сервер в `.env`)
             └─ всё остальное ─► WAN напрямую (zapret2 autohostlist ловит новые блокировки)
```

Дополнительно:
- **QUIC (UDP/443) запрещён** (firewall-правило `block_quic`, REJECT) — клиенты сразу уходят на TCP, который обходит zapret2.
- **Flow offloading выключен** — иначе трафик клиентов идёт мимо zapret2. Не включать!

## 2. Железо и прошивка

- Продаётся как **wwGate AX3000**, фактически **Huasifei WH3000R NAND** (MT7981B, 256 МБ SPI‑NAND, 512 МБ RAM).
  Проверено по DTS, разметке флеша, GPIO, PHY — идентичны.
- Прошита **официальная OpenWrt 25.12.5**, профиль `huasifei_wh3000r-nand`
  (первый раз — `sysupgrade -F`, т.к. заводское имя платы `wwgate,ax3000`).
- Дальнейшие обновления — обычным путём: образ `huasifei_wh3000r-nand` с downloads.openwrt.org
  или Attended Sysupgrade в LuCI. После обновления переустановить пакеты (раздел 4).
- Менеджер пакетов — **apk** (не opkg).

## 3. Быстрый старт (новая машина)

```bash
git clone https://github.com/<you>/wwgate-openwrt-bypass && cd wwgate-openwrt-bypass
cp .env.example .env                  # заполнить: пароли, VLESS-ссылку (VSL) — в одинарных кавычках
chmod 600 .env
git config core.hooksPath .githooks   # pre-commit хук блокирует коммит секретов
bin/r 'uptime'                        # проверка SSH (ключ ~/.ssh/id_ed25519 должен быть на роутере)
```

Доступ:
- LuCI: http://192.168.2.1 (root / пароль из `.env`)
- SSH: `bin/r` (интерактивно) или `bin/r 'команда'`; в циклах — `bin/r -n '...'` (не читает stdin).

## 4. Установленные компоненты

| Компонент | Версия | Где настраивать |
|---|---|---|
| OpenWrt | 25.12.5 | LuCI |
| zapret2 + luci-app-zapret2 ([remittor/zapret-openwrt](https://github.com/remittor/zapret-openwrt)) | 0.9.20260307 | `config/zapret2.NFQWS2_OPT.txt`, LuCI → Службы → Zapret2 |
| podkop + luci-app-podkop ([itdoginfo/podkop](https://github.com/itdoginfo/podkop)) | 0.7.22 | LuCI → Службы → Podkop, `config/podkop.uci` |
| sing-box | 1.13.21 | генерируется podkop (`/etc/sing-box/config.json`) |

Пакеты скачиваются в `packages/` (в git не попадают) и ставятся так:
```bash
bin/r 'cat > /tmp/x.apk' < packages/.../x.apk
bin/r 'apk add --allow-untrusted /tmp/x.apk'
```

## 5. Повседневные операции

| Задача | Команда |
|---|---|
| Бэкап настроек роутера | `scripts/backup.sh` → `backups/<дата>/` (в git не попадает) |
| Применить стратегию/hostlist zapret2 | правим `config/zapret2.NFQWS2_OPT.txt` / `config/zapret2-hosts-user.txt` → `scripts/apply-zapret2.sh` |
| Сайт в обход через zapret2 | добавить домен в `config/zapret2-hosts-user.txt` и `config/zapret-ok-domains.lst` → `scripts/apply-zapret2.sh`, затем `bin/r 'cat > /etc/podkop/zapret-ok.lst' < config/zapret-ok-domains.lst` и `bin/r '/etc/init.d/podkop restart'` |
| Сайт в обход через VLESS | LuCI → Podkop → main → User domains, или `bin/r 'uci add_list podkop.main.user_domains=site.com; uci commit podkop; /etc/init.d/podkop restart'` |
| Проверка с Android | `DEV=<ip:port> scripts/phone-check.sh` (см. раздел 7) |
| Диагностика podkop | `bin/r 'podkop global_check'` |
| Статус | `bin/r 'pidof nfqws2 sing-box dnsmasq; nft list tables'` — таблицы `fw4`, `zapret2`, `PodkopTable` |
| Выключить обход | `bin/r '/etc/init.d/zapret2 stop; /etc/init.d/podkop stop'` |

⚠️ `podkop restart` на 5–20 с отключает DNS у всех клиентов — не перезапускать без необходимости.

## 6. Результаты проверки (2026‑09‑24, с Android через wwGate)

| Сервис | Путь | Статус |
|---|---|---|
| YouTube (сайт, приложение, видео) | zapret2 | ✅ Android + iPhone |
| X, Discord, rutracker, meduza, bbc… (463 домена) | zapret2 | ✅ |
| Telegram | VLESS | ✅ DC и telegram.org |
| WhatsApp, Instagram | VLESS (meta) | ✅ сайт; звонки — ждут подтверждения |
| ChatGPT, Claude, Spotify, Notion | VLESS | ✅ (403 у curl — Cloudflare-челлендж, в браузере ок) |
| Gemini | VLESS | ✅ (первый запрос до ~15 с) |
| LG TV | — | ❌ на паузе, см. `CLAUDE.md` → TODO |

---

## 7. Как тестировать (важно!)

**Тесты с Мака недостоверны** — на нём свой VPN/обход. Валидные способы:

1. **Android по adb (Wi‑Fi)** — телефон в сети wwGate, «Отладка по Wi‑Fi» включена:
   ```bash
   adb mdns services                 # найдёт 192.168.2.x:PORT
   adb connect 192.168.2.x:PORT
   adb push curl /data/local/tmp/    # статический curl aarch64 (github.com/stunnel/static-curl, musl)
   DEV=192.168.2.x:PORT scripts/phone-check.sh
   ```
   Android-curl не видит системный DNS → в скрипте резолв делается на роутере и передаётся через `--resolve`.
   Для чистоты выключить мобильные данные: `adb shell svc data disable` (потом `enable`!).
   Реальное приложение: `adb shell am start -a android.intent.action.VIEW -d "https://www.youtube.com/watch?v=..." com.google.android.youtube`
   и `adb exec-out screencap -p > s.png`.
2. **Наблюдение за клиентом на роутере** (iPhone, ТВ):
   ```bash
   bin/r 'uci set dhcp.@dnsmasq[0].logqueries=1; uci commit dhcp; /etc/init.d/dnsmasq reload'  # DNS в logread
   bin/r 'sysctl -w net.netfilter.nf_conntrack_acct=1'   # байты по соединениям в /proc/net/nf_conntrack
   bin/r 'apk add tcpdump-mini'                          # захват: cmd & P=$!; sleep N; kill $P  (нет `timeout`)
   ```
   DPI-блокировка: соединение `ESTABLISHED`, `up` ~1–2 КБ, `down` ~60 байт или ~1.4 КБ и дальше тишина.
   IP-блокировка: `SYN_SENT` без ответа. После диагностики — всё выключить.
3. **С самого роутера** — два curl'а с разным ClientHello:
   - `curl` (mbedTLS, маленький hello ~270 байт — как iPhone),
   - `/tmp/curl-ossl` (OpenSSL 4 + ML-KEM, большой hello ~1.8 КБ — как Android/Chrome). Лежит в `/tmp` → после ребута залить заново.

---

## Подбор стратегий: руководство для Claude / другого агента

> Цель: найти desync-стратегию zapret2, которая работает для **всех реальных клиентов**, а не только для curl.
> ТСПУ регулярно меняет поведение — стратегия, работавшая месяц назад, может перестать.

### Шаг 0. Классифицируй блокировку, прежде чем что-то подбирать

| Симптом (с роутера, zapret2 выключен) | Тип | Что делать |
|---|---|---|
| TCP connect не проходит (`time_connect=0`, `SYN_SENT`) | блок по IP | zapret не поможет → VLESS (podkop `main`) |
| TCP ок, TLS висит / RST после ClientHello | DPI по SNI | подбирать стратегию zapret2 |
| TLS ок, но сервис отвечает 403/451 «not available in your country» | геоблок сервиса | только VLESS |
| Работает, но загрузка замирает после ~16 КБ | DPI-троттлинг | стратегия zapret2 |
| Нет A-записи у 77.88.8.8 | DNS-блок / мёртвый домен | проверить через DoH, иначе VLESS |

Быстро: `bin/r "curl -s -o /dev/null -m 6 -w '%{time_connect} %{time_appconnect} %{http_code}\n' https://HOST/"`.

### Шаг 1. Blockcheck (автоматический перебор)

```bash
bin/r 'cat > /tmp/curl-ossl; chmod +x /tmp/curl-ossl' < curl   # static-curl aarch64 musl
bin/r '/etc/init.d/zapret2 stop; cd /opt/zapret2; \
  CURL=/tmp/curl-ossl BATCH=1 DOMAINS="www.youtube.com redirector.googlevideo.com" IPVS=4 \
  ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=0 ENABLE_HTTPS_TLS13=1 ENABLE_HTTP3=0 \
  REPEATS=2 PARALLEL=1 SCANLEVEL=quick SKIP_DNSCHECK=1 SKIP_IPBLOCK=1 \
  setsid ./blockcheck2.sh > /tmp/bc.log 2>&1 < /dev/null &'
bin/r 'grep -B4 "!!!!! AVAILABLE" /tmp/bc.log | grep "^- curl"'   # найденные рабочие
```
- Длится 10+ минут. После — **обязательно** `bin/r '/etc/init.d/zapret2 start'`.
- Если прервали: `nft delete table inet blockcheckNNNN` и убить лишний `nfqws2` (`ps w | grep nfqws2`).
- Не запускай, пока пользователь смотрит видео, — на время теста обход выключен. Предупреди его.

### Шаг 2. Отбор кандидатов вручную (быстро, 1–2 мин)

Blockcheck проверяет одним curl и одним хостом. Реальность шире. Прогоняй кандидатов матрицей
«**2 клиента × критичные хосты × N попыток**»:

```bash
T='for c in curl /tmp/curl-ossl; do for h in www.youtube.com youtubei.googleapis.com \
   rr1---sn-4g5edns6.googlevideo.com i.ytimg.com; do ok=0; for i in 1 2 3; do \
   x=$($c -s -o /dev/null -m 4 -w "%{http_code}" https://$h/); [ "$x" != 000 ] && ok=$((ok+1)); \
   done; printf "%s " $ok; done; printf "| "; done'
# для каждого кандидата: записать opt-файл → scripts/apply-zapret2.sh FILE </dev/null → bin/r -n "$T"
```
Шаблон одного профиля:
```
--filter-tcp=443
--filter-l7=tls <HOSTLIST>
--payload=tls_client_hello
--lua-desync=<кандидат>
```
Критерий: **все ячейки N/N для обоих curl**. Реальные `rrN---sn-*.googlevideo.com` бери из DNS-лога клиента.
Для разных групп сайтов (Google vs Cloudflare) допустимы разные профили: первый профиль с
`--hostlist=/opt/zapret2/ipset/zapret-hosts-google.txt`, второй — `<HOSTLIST>`.

### Шаг 3. Подтверждение на реальных клиентах

1. Android: `scripts/phone-check.sh` + видео в приложении YouTube + скриншот.
2. iPhone: пользователь включает видео, ты смотришь conntrack (байты `down` на googlevideo должны расти до мегабайт).
3. Только после этого — зафиксировать в `config/zapret2.NFQWS2_OPT.txt`, `scripts/backup.sh`, обновить README и CLAUDE.md.

### Уроки (Ростелеком, сентябрь 2026)

- Дефолтная стратегия пакета zapret2 **не работает**.
- `multidisorder:pos=1,midsld` проходит для youtube.com, но **ломает** `youtubei.googleapis.com`
  (API приложений → «вечная загрузка») и видео на **iPhone** (маленький ClientHello: сервер отвечает
  ServerHello, а сертификаты ТСПУ режет).
- Google/YouTube: `fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,dupsid,padencap:repeats=1`.
- Cloudflare-сайты (X, Discord, rutracker, LinkedIn): fake-only не работает → `multisplit:pos=10,midsld:seqovl=1`.
- `oob` и `fake(repeats=3) + multisplit seqovl` — не работают вообще.
- Тест с Мака показывал «всё работает», когда на телефонах не работало.
- Flow offloading (заводская настройка) полностью отключал обход для клиентов.
- QUIC надо отклонять (REJECT, не DROP), иначе клиенты висят на таймауте.

### Массовая проверка доменов (что лечит zapret, а что — только VLESS)

Список `russia_inside` ([itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains)) минус
геоблоки и сервисные списки → прогон через zapret2 напрямую (резолв через 77.88.8.8, чтобы обойти fakeip podkop),
16 параллельных циклов (в busybox нет `xargs -P`/`split` — делить через `awk`).
Результат — `config/zapret-test-results.txt`; прошедшие (кроме HTTP 451) — `config/zapret-ok-domains.lst`
→ на роутере `/etc/podkop/zapret-ok.lst` (исключение podkop `yt_direct`: напрямую через zapret2).
Повторять раз в 1–2 месяца.

---

## 8. Структура репозитория

```
bin/r                     SSH-обёртка (читает .env)
scripts/                  apply-zapret2, backup, phone-check, check (Mac — не для вердиктов)
config/                   источник правды: стратегии, hostlist'ы, uci-экспорты (секреты замаскированы)
config/legacy-zapret1/    старый zapret v1 (удалён с роутера)
.githooks/pre-commit      блокирует коммит секретов
.env.example              шаблон секретов
CLAUDE.md                 правила и TODO для ИИ-агентов
backups/ firmware/ packages/   локально, в git не попадают
```

`backups/stock-25.12.3/` — **дамп заводской прошивки** (BL2, u-boot-env, **Factory = калибровка Wi‑Fi и MAC**, FIP,
UBI kernel/rootfs). Хранить вне git в надёжном месте — без Factory Wi‑Fi не восстановить.

## 9. Безопасность и git

- Секреты — только в `.env` (gitignored). В `config/podkop.uci` UUID VLESS замаскирован (`vless://***@`).
- `backups/` не коммитить никогда: там `/etc/shadow`, Wi‑Fi PSK и ключи SSH-хоста.
- `.githooks/pre-commit` блокирует: `.env`, `backups/`, VLESS/VMess/Trojan-ссылки с UUID, приватные ключи,
  `option key '...'` из uci, `PASSWORD=...`, а также любые значения паролей/VSL из локального `.env`.
- Перед экспортом uci: `uci export podkop | sed -E "s#vless://[^@]*@#vless://***@#"`.

## 10. Траблшутинг

| Проблема | Проверка / решение |
|---|---|
| Нет интернета у клиентов | `bin/r 'ifstatus wan'` (адрес 192.168.1.x), `bin/r 'nslookup ya.ru 127.0.0.1'` |
| DNS не отвечает | обычно идёт перезапуск podkop — подождать 20 с; `bin/r 'pidof dnsmasq sing-box'` |
| YouTube снова тормозит | раздел «Подбор стратегий», шаги 0–3 |
| Сайт не открывается | классифицировать (шаг 0) → добавить в zapret2 или VLESS |
| VLESS не работает | `bin/r 'podkop check_proxy'`; временно `uci set podkop.main.mixed_proxy_enabled=1` → `curl -x socks5h://192.168.2.1:2080 https://ifconfig.me` (потом выключить!) |
| После обновления прошивки пропал обход | переустановить zapret2/podkop из `packages/`, `scripts/apply-zapret2.sh`, проверить offload=0 и `block_quic` |
