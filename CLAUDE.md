# CLAUDE.md — wwGate AX3000 (OpenWrt) bypass router

Home router that bypasses Russian (RKN/TSPU) blocks and foreign geo-blocks for all Wi‑Fi clients
(phones, LG TV) transparently. This repo is the control/ops project for it — no app code.

## Topology

```
ISP Rostelecom ─ RT-GPON-XXXX (192.168.1.1) ─LAN──WAN─ wwGate (WAN 192.168.1.23 DHCP)
                                                         LAN 192.168.2.1/24, Wi‑Fi wwGate-2.4G / wwGate-5G (WPA2)
```

- Hardware: sold as **wwGate AX3000** = **Huasifei WH3000R NAND** (MT7981B, 256 MB SPI‑NAND, 512 MB RAM).
- Firmware: official **OpenWrt 25.12.5**, profile `huasifei_wh3000r-nand` (flashed with `sysupgrade -F`).
  `board_name` is now `huasifei,wh3000r-nand`; future upgrades use that profile.
- Package manager is **apk** (not opkg). Router busybox lacks `timeout`, `split`, `xargs -P`, `nc -z`.

## Traffic routing (decision order)

1. **podkop exclusion `yt_direct`** → sing-box `direct-out` → WAN → **zapret2** (DPI desync):
   YouTube (community `youtube` + user domains) + `/etc/podkop/zapret-ok.lst`
   (463 RKN-blocked domains verified to open via zapret2, see `config/zapret-ok-domains.lst`).
2. **podkop `main`** → **VLESS** (`VSL` in `.env`, exit Frankfurt, server in `.env`):
   community `russia_inside` (rest of RKN list + geo-blocks: ChatGPT, Claude, Spotify, Notion…),
   `google_ai` (Gemini), `telegram`, `meta` (WhatsApp calls + Instagram — shared Meta IPs), `discord`, `twitter`.
3. Everything else → direct. zapret2 `autohostlist` catches newly DPI-blocked hosts.

- YouTube domains bypass sing-box entirely: `/etc/dnsmasq.direct.servers` (`config/dnsmasq-direct.servers`,
  dnsmasq `serversfile`) resolves them via 77.88.8.8 to real IPs → kernel path → zapret2. podkop wipes
  dnsmasq `server` list on start, but leaves `serversfile` alone.
- DNS: dnsmasq → sing-box `127.0.0.42` (fakeip 198.18.0.0/15 for listed domains) → 77.88.8.8.
- QUIC (UDP/443) LAN→WAN is **REJECTed** (fw rule `block_quic`) so clients fall back to TCP.
- **Flow offloading (sw+hw) must stay OFF** — otherwise client traffic bypasses zapret.

## zapret2 strategy (Rostelecom, verified 2026‑09‑24)

`config/zapret2.NFQWS2_OPT.txt`:
- Profile 1 (Google/YouTube hostlist): `fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,dupsid,padencap`.
  `multidisorder` breaks iPhone (small ClientHello) and `youtubei.googleapis.com`.
- Profile 2 (`<HOSTLIST>` = user list + autohostlist): `multisplit:pos=10,midsld:seqovl=1`.
- The package default strategy does NOT work on Rostelecom.

## Rules for working here

- **Never trust tests from the Mac** — it has its own VPN/bypass. Test from Android over adb
  (`adb mdns services` → `adb connect <ip:port>`; phone has static curl at `/data/local/tmp/curl`,
  needs `--resolve` because it can't read Android DNS) or observe clients on the router
  (dnsmasq `logqueries=1`, `sysctl net.netfilter.nf_conntrack_acct=1`, `tcpdump`). Turn diagnostics off after.
- Router-side realistic TLS tests: OpenSSL static curl at `/tmp/curl-ossl` (ML-KEM, like Android) and
  stock mbedTLS `curl` (small hello, like iPhone). A strategy must pass **both**.
- Always check `youtubei.googleapis.com` and real `rrN---sn-*.googlevideo.com` hosts, not only youtube.com.
- After `uci set zapret2...` run `/opt/zapret2/sync_config.sh` then restart (or use `scripts/apply-zapret2.sh`).
- `podkop restart` drops DNS for ~5–20 s — avoid unnecessary restarts while the user is using the network.
- **TSPU temporary penalty**: after bursts of bypass traffic (mass domain tests, long candidate loops) TSPU
  can silently drop ServerHello for working strategies for several minutes; it recovers by itself. Don't
  "fix" a strategy right after a mass test — wait 5–10 min and retest. Run mass tests at night / in small batches.
- An interrupted blockcheck leaves `nft table inet blockcheckNNNN` + stray `nfqws2` — delete them.
- ssh inside `while read` loops eats stdin — use `bin/r -n` or arrays.
- Secrets live only in `.env` (gitignored). Never print `VSL` / passwords; mask UUID in exports.

## Commands

| Command | Purpose |
|---|---|
| `bin/r ['cmd']` | SSH to router (key auth); `bin/r -n` for no-stdin |
| `scripts/apply-zapret2.sh [opt-file]` | Push strategy + hostlist to zapret2, restart |
| `scripts/phone-check.sh` | Site checks from Android via adb (`DEV=ip:port`) |
| `scripts/check.sh` | Site checks from Mac via en0 — **not valid for verdicts** |
| `scripts/backup.sh` | Router config backup → `backups/<date>/` |
| `bin/r 'podkop global_check'` | podkop diagnostics |

## Layout

- `config/` — source of truth pushed to router: zapret2 strategy/hostlists, podkop/firewall/zapret2 uci exports,
  zapret-ok domain list + raw test results. `config/legacy-zapret1/` — old zapret v1 (removed from router).
- `backups/stock-25.12.3/` — **vendor firmware dump** (BL2, u-boot-env, Factory = Wi‑Fi calibration/MACs, FIP,
  UBI kernel/rootfs). Keep forever.
- `packages/` — installed .apk (zapret, zapret2, podkop). `firmware/` — OpenWrt image + sha256sums.

## TODO / next tasks

### LG TV (paused by user)
- [ ] LG webOS TV `192.168.2.168` can't open YouTube; webOS thinks there's no internet.
  Capture: TV gets SYN‑ACK but its ClientHello (194 B) is never ACKed by servers (Google 172.217.19.238,
  LG `ru.lgtvsdp.com` 158.255.4.34). TV TCP timestamps are near 2^32 and wrap. Router itself reaches
  `ru.lgtvsdp.com` fine (HTTP 200).
- [ ] Next steps: tcpdump on `wan` for TV flows (does ClientHello leave the router? mangled by zapret2?);
  retry with zapret2 stopped / TV IP in `nozapret`; check `nf_conntrack_tcp_be_liberal`, PAWS; try TV on 5 GHz;
  try DIAL cast from phone.

### Security
- [ ] Root password was given to Claude in chat and may equal the Wi‑Fi password — set a unique strong root password, then
  disable SSH password auth (`dropbear PasswordAuth off`, key-only).
- [ ] LuCI is HTTP-only — install `luci-ssl`/uhttpd TLS or restrict LuCI to wired/SSH tunnel.
- [ ] VLESS is **ws without TLS** — traffic to the VLESS server is plaintext‑framed and easily DPI‑fingerprinted;
  move server to VLESS+Reality (or ws+TLS) to avoid blocking and leaks.
- [ ] `.env` holds plaintext secrets — keep out of git/cloud sync; consider macOS Keychain.
- [ ] Packages installed with `--allow-untrusted` (zapret2, podkop) — pin versions, verify release checksums on updates.
- [ ] Phone: disable Wireless debugging (adb) when done; remove `/data/local/tmp/curl`.
- [ ] Consider guest Wi‑Fi / client isolation for IoT (TV) and a separate SSID for admin devices.
- [ ] Check WAN input policy (`REJECT`), no ports exposed; ensure podkop `mixed_proxy_enabled=0` (open SOCKS on LAN).
- [ ] Enable automatic list updates sanity (podkop cron `list_update` daily) and a monthly backup (`scripts/backup.sh`).

### Other
- [ ] Reboot test: confirm podkop + zapret2 + fw rules all come up together after power loss.
- [ ] WhatsApp calls & Telegram media — user confirmation on real devices.
- [ ] Re-run `config/zapret-ok` mass test periodically (TSPU changes); move failing domains back to VLESS.
- [ ] VLESS cold-start latency (first request up to ~15 s, e.g. Gemini) — try sing-box `multiplex`/keepalive.
- [ ] Optional: tg-ws-proxy as Telegram fallback without VLESS (needs per-device proxy settings).
- [ ] Wi‑Fi: phones/TV to 5 GHz where supported (2.4 GHz has 6 clients; a test Android phone linked at 65 Mbit/s).
