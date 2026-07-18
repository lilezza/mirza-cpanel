# Mirza cPanel CLI

Yek VPS + **yek** cPanel account → nasb / manage chandin bot Mirza (har bot = yek subdomain).

Repo: https://github.com/lilezza/mirza-cpanel  
Script: https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh

---

## 1) Pishniaz

- VPS ba **WHM/cPanel** (root access)
- PHP **8.2** (EasyApache / MultiPHP)
- Domain rooye hamin cPanel account
- Baraye **har bot** too Cloudflare:
  - Record **A**: `bot1` → IP VPS
  - Abr = **DNS only (khakestari)** — NA proxied (narenji)

> Official `install.sh` Mirza rooye cPanel **nasan** — Apache/path joda dare. In CLI baraye cPanel-e.

---

## 2) Nasb CLI (yekbar)

Ba root rooye server:

```bash
curl -fsSL https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh -o /usr/local/bin/mirza
chmod +x /usr/local/bin/mirza
mirza
```

Ba’d prompt miad:

```text
mirza>
```

---

## 3) Command ha

| Command | Chi mikone |
|---------|------------|
| `help` | list command ha |
| `steps` | rahnama-ye kootah |
| `install` | nasb bot jadid (subdomain + DB + webhook + cron) |
| `uninstall` | hazf kamel bot (files + DB + cron + webhook + subdomain) |
| `list` | list bot haye nasb shode |
| `info` | joziyat yek bot (URL, DB, token, …) |
| `update` | update code-e **yek** bot (config + DB mimunan) |
| `update-all` | update **hame** bot ha |
| `self-update` | update **khode** CLI mirza az GitHub (bedoon curl dasti) |
| `restore` | import file `.sql` (backup ghadimi) |
| `backup` | export DB → `/root/DOMAIN-date.sql` |
| `phpmyadmin` | link cPanel + info DB (+ one-time login age beshe) |
| `set-token` | avaz token + set webhook |
| `set-admin` | avaz admin chat ID |
| `webhook` | set / check webhook |
| `setup-cli` | nasb `mirza` too `/usr/local/bin` |
| `exit` | khoruj az CLI |

---

## 4) Nasb bot jadid

```text
mirza> install
```

Azat miporse:

1. cPanel username (yekbar zakhire mishe)
2. Root domain (mesl `mirza.shop`)
3. Subdomain label (mesl `bot1` → `bot1.mirza.shop`)
4. Token / username bot / admin ID

Khodesh:

- subdomain misaze
- database + user (UAPI)
- Mirza download mikone
- `config.php` por mikone
- AutoSSL, webhook, cron

Bad az nasb:

- Bot: `https://bot1.mirza.shop`
- Admin: `https://bot1.mirza.shop/admin.php`
- Secrets: `/root/.mirza-cpanel/credentials.txt`

Telegram → `@bot` → `/start`

---

## 5) Restore backup (bot ghadimi → jadid)

1. Aval bot jadid ro `install` kon (behtar ba **hamun token** ghadimi)
2. File `.sql` ro upload kon rooye server
3. Dakhel CLI:

```text
mirza> restore
```

Bot ro entekhab kon + path-e `.sql`

4. **Dasti** too admin panel:
   - domain / subscription link / panel URL → domain **jadid**
   - age gateway dari, callback URL ham update kon
5. `/start` bezan

**Rahe digar:** `phpmyadmin` → login cPanel → phpMyAdmin → Import → `.sql`

---

## 6) Update (vaghti Mirza version mide)

```text
mirza> update          # yek bot
mirza> update-all      # hame
```

Chi **mimumune**: `config.php` + data-e database  
Chi **taze mishe**: code az GitHub + `table.php` (schema)

Pishnahad ghabl az update:

```text
mirza> backup
```

> Official `mirza update` / `install.sh` rooye cPanel use **nakon**.

---

## 7) Avaz token / admin

```text
mirza> set-token
mirza> set-admin
```

`set-token` automatic webhook ro ham set mikone.

---

## 8) phpMyAdmin

```text
mirza> phpmyadmin
```

Neshoon mide:

- link cPanel (`:2083`)
- DB name / user / password
- age beshe, one-time login link

Az cPanel → **Databases → phpMyAdmin**.

---

## 9) File ha / meta

| Path | Chiye |
|------|--------|
| `/usr/local/bin/mirza` | khode CLI |
| `/root/.mirza-cpanel/account.conf` | cPanel user + root domain |
| `/root/.mirza-cpanel/bots/*.env` | meta har bot |
| `/root/.mirza-cpanel/credentials.txt` | password/token ha |

---

## 10) Troubleshooting kootah

| Moshkel | Check |
|---------|--------|
| SSL / AutoSSL fail | Cloudflare grey-cloud? DNS A dorost? |
| Webhook `404` | Docroot bayad `public_html/...` bashe (v1.2+). `curl -I https://DOMAIN/index.php` |
| DB access denied | Script ba prefix `user_db` + mysql GRANT fallback (v1.2+) |
| Webhook fail | SSL amade? `mirza> webhook` |
| Jadval nist | `https://DOMAIN/table.php` ya `info` |
| Bot javab nemide | token, webhook, `/start` |
| Cron kar nemikone | `crontab -u CPUSER -l` |

### Update CLI rooye server (bad az push)

```bash
curl -fsSL https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh -o /usr/local/bin/mirza
chmod +x /usr/local/bin/mirza
mirza
# bayad v1.2.0 neshun bede
```

---

## License / note

In wrapper baraye nasb rooye **cPanel** neveshte shode.  
Kode asli bot: [mahdiMGF2/mirzabot](https://github.com/mahdiMGF2/mirzabot)

### Changelog

**v1.3.5**
- `self-update` / `update-cli` — update khode CLI az GitHub (bedoon curl dasti)

**v1.3.4**
- Backup cron: run `backupbot.php` via `ea-php82` CLI (cPanel web PHP has `exec` disabled → HTTP curl backup always failed)
- `backupbot.php`: prefer `/usr/bin/mysqldump`

**v1.3.3**
- Patch `cronbot/backupbot.php`: remove `--ssl-mode=DISABLED` (MariaDB unknown variable → backup silent fail)

**v1.3.2**
- `restore`: auto-fix collation MySQL 8 (`utf8mb4_0900_ai_ci`) → MariaDB (`utf8mb4_unicode_ci`) — error `#1273`

**v1.3.1**
- Patch Mirza Rebecca: vorud panel digar 500 nemide (invoice SQL ba `Service_location`)
- `password_panel` → `TEXT` (API key / JWT toolani)

**v1.3.0**
- Add `uninstall` — hazf kamel bot (webhook, cron, files, DB, subdomain, meta)

**v1.2.0**
- Fix docroot: file-ha miran to `/home/USER/public_html/SUB.DOMAIN` (digar 404 webhook)
- Fix MySQL: UAPI ba esm prefix-dar (`user_dbname`) + fallback `GRANT` ba root
- Install fail mishe age DB login kar nakone
- Check `index.php` HTTP status bad az nasb
- Resolve docroot az cPanel userdata
