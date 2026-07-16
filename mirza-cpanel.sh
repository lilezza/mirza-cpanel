#!/bin/bash
###############################################################################
#  MIRZA  —  cPanel Multi-Bot CLI
#  ---------------------------------------------------------------------------
#  Yek VPS + yek cPanel account. Chand bot = chand subdomain.
#
#  Install CLI (yekbar, ba root):
#    curl -fsSL https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh -o /usr/local/bin/mirza && chmod +x /usr/local/bin/mirza
#    mirza
#
#  Ya mostaghim:
#    bash mirza-cpanel.sh
###############################################################################
set -u

VERSION="1.3.1"
PHP_EA="ea-php82"
REPO_TAR="https://github.com/mahdiMGF2/mirzabot/archive/refs/heads/main.tar.gz"
META_ROOT="/root/.mirza-cpanel"
CONF_FILE="${META_ROOT}/account.conf"
BOTS_DIR="${META_ROOT}/bots"
CREDS_FILE="${META_ROOT}/credentials.txt"
BIN_PATH="/usr/local/bin/mirza"

C_OK=$'\e[92m'; C_BAD=$'\e[91m'; C_WARN=$'\e[93m'; C_INFO=$'\e[96m'
C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; CR=$'\e[0m'

ok(){   echo -e "  ${C_OK}OK${CR} $*"; }
bad(){  echo -e "  ${C_BAD}x${CR} $*"; }
warn(){ echo -e "  ${C_WARN}!${CR} $*"; }
info(){ echo -e "  ${C_INFO}>${CR} $*"; }
die(){  bad "$*"; return 1 2>/dev/null || exit 1; }

need_root(){ [ "$(id -u)" -eq 0 ] || { bad "Ba root ejra kon (sudo -i)."; return 1; }; }
need_tools(){
  command -v whmapi1 >/dev/null 2>&1 || { bad "whmapi1 nist — WHM/cPanel lazem-e."; return 1; }
  command -v uapi    >/dev/null 2>&1 || { bad "uapi nist."; return 1; }
  command -v mysql   >/dev/null 2>&1 || { bad "mysql nist."; return 1; }
  command -v curl    >/dev/null 2>&1 || { bad "curl nist."; return 1; }
}

ensure_meta(){
  mkdir -p "$BOTS_DIR"
  chmod 700 "$META_ROOT" "$BOTS_DIR" 2>/dev/null || true
  touch "$CREDS_FILE" 2>/dev/null || true
  chmod 600 "$CREDS_FILE" 2>/dev/null || true
}

sanitize(){ echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

# ---------- account ----------
load_account(){
  ensure_meta
  CPUSER=""; ROOT_DOMAIN=""
  if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
  fi
}

save_account(){
  ensure_meta
  cat > "$CONF_FILE" <<EOF
CPUSER='${CPUSER}'
ROOT_DOMAIN='${ROOT_DOMAIN}'
EOF
  chmod 600 "$CONF_FILE"
}

ask_account_once(){
  load_account
  if [ -n "${CPUSER:-}" ] && [ -n "${ROOT_DOMAIN:-}" ]; then
    info "Account: ${CPUSER} | root domain: ${ROOT_DOMAIN}"
    read -rp "  Hamin? (y/n) [y]: " yn; yn="${yn:-y}"
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then return 0; fi
  fi
  read -rp "  cPanel username: " CPUSER
  [ -n "${CPUSER}" ] || { bad "Username khali."; return 1; }
  whmapi1 accountsummary user="$CPUSER" >/dev/null 2>&1 || { bad "Account '$CPUSER' vojod nadare."; return 1; }
  read -rp "  Root domain (mesl mirza.shop): " ROOT_DOMAIN
  ROOT_DOMAIN="${ROOT_DOMAIN,,}"
  [ -n "${ROOT_DOMAIN}" ] || { bad "Domain khali."; return 1; }
  save_account
  ok "Zakhire shod."
}

# ---------- bot meta ----------
bot_meta_path(){ echo "${BOTS_DIR}/${1}.env"; }

save_bot_meta(){
  local f; f="$(bot_meta_path "$DOMAIN")"
  cat > "$f" <<EOF
DOMAIN='${DOMAIN}'
SUB='${SUB}'
ROOT_DOMAIN='${ROOT_DOMAIN}'
CPUSER='${CPUSER}'
DOCROOT='${DOCROOT}'
DBNAME='${DBNAME}'
DBUSER='${DBUSER}'
DBPASS='${DBPASS}'
BOT_TOKEN='${BOT_TOKEN}'
BOT_USERNAME='${BOT_USERNAME}'
ADMIN_ID='${ADMIN_ID}'
EMAIL='${EMAIL:-}'
INSTALLED_AT='$(date -Iseconds 2>/dev/null || date)'
EOF
  chmod 600 "$f"
  {
    echo "======== $(date) ========"
    echo "Domain      : ${DOMAIN}"
    echo "Docroot     : ${DOCROOT}"
    echo "DB          : ${DBNAME} / ${DBUSER}"
    echo "DB pass     : ${DBPASS}"
    echo "Bot token   : ${BOT_TOKEN}"
    echo "Bot user    : @${BOT_USERNAME}"
    echo "Admin ID    : ${ADMIN_ID}"
    echo
  } >> "$CREDS_FILE"
}

load_bot_meta(){
  local f; f="$(bot_meta_path "$1")"
  [ -f "$f" ] || { bad "Meta baraye '$1' nist. Aval: list"; return 1; }
  # shellcheck disable=SC1090
  source "$f"
}

list_bot_domains(){
  ensure_meta
  local f
  shopt -s nullglob
  for f in "$BOTS_DIR"/*.env; do basename "$f" .env; done
  shopt -u nullglob
}

pick_bot(){
  local bots=() i=1 choice d
  while IFS= read -r d; do [ -n "$d" ] && bots+=("$d"); done < <(list_bot_domains)
  if [ "${#bots[@]}" -eq 0 ]; then bad "Hich bot-i nist. Aval install kon."; return 1; fi

  echo
  info "Bot ha:"
  for d in "${bots[@]}"; do
    printf "    %s) %s\n" "$i" "$d"
    i=$((i + 1))
  done
  echo
  read -rp "  Shomare bot: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || { bad "Invalid."; return 1; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#bots[@]}" ] || { bad "Out of range."; return 1; }
  DOMAIN="${bots[$((choice - 1))]}"
  load_bot_meta "$DOMAIN" || return 1
}

php_bin(){
  if [ -x "/usr/local/bin/${PHP_EA}" ]; then echo "/usr/local/bin/${PHP_EA}"
  elif command -v "$PHP_EA" >/dev/null 2>&1; then command -v "$PHP_EA"
  else echo "php"; fi
}

set_php(){
  whmapi1 php_set_vhost_versions version="$PHP_EA" vhost="$DOMAIN" >/dev/null 2>&1 \
    && ok "PHP $PHP_EA → $DOMAIN" \
    || warn "PHP dasti: MultiPHP → $DOMAIN → 8.2"
}

fix_dirs(){
  chown -R "${CPUSER}:${CPUSER}" "$DOCROOT"
  find "$DOCROOT" -type d -exec chmod 755 {} \;
  find "$DOCROOT" -type f -exec chmod 644 {} \;
  touch "$DOCROOT/error_log"
  chown "${CPUSER}:${CPUSER}" "$DOCROOT/error_log" 2>/dev/null || true
  chmod 664 "$DOCROOT/error_log" 2>/dev/null || true
}

run_table_php(){
  local php; php="$(php_bin)"
  info "table.php..."
  if [ -f "$DOCROOT/table.php" ]; then
    (cd "$DOCROOT" && sudo -u "$CPUSER" "$php" table.php) >/dev/null 2>&1 \
      || "$php" "$DOCROOT/table.php" >/dev/null 2>&1 || true
  fi
  curl -s --max-time 15 --resolve "${DOMAIN}:80:127.0.0.1"  "http://${DOMAIN}/table.php"  >/dev/null 2>&1 || true
  curl -sk --max-time 15 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/table.php" >/dev/null 2>&1 || true
  if mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DBNAME}';" 2>/dev/null | grep -qvE '^0$'; then
    ok "Jadval ha OK."
  else
    warn "Jadval detect nashod — ba'dan: https://${DOMAIN}/table.php"
  fi
}

wait_ssl(){
  info "AutoSSL..."
  /usr/local/cpanel/bin/autossl_check_cpuser "$CPUSER" >/dev/null 2>&1 &
  local i SSL_OK=0
  for i in $(seq 1 8); do
    sleep 6
    if echo | timeout 6 openssl s_client -servername "$DOMAIN" -connect "127.0.0.1:443" 2>/dev/null \
        | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then SSL_OK=1; break; fi
  done
  [ "$SSL_OK" = 1 ] && ok "SSL amade." || warn "SSL hanoz amade nist (DNS grey-cloud check)."
}

set_webhook(){
  info "Webhook..."
  local WH
  WH=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/setWebhook?url=https://${DOMAIN}/index.php")
  if echo "$WH" | grep -q '"ok":true'; then
    ok "https://${DOMAIN}/index.php"
  else
    warn "Webhook: $WH"
  fi
}

install_crons(){
  info "Cron → $DOMAIN"
  local CRON_TMP j m f
  CRON_TMP="$(mktemp)"
  crontab -u "$CPUSER" -l 2>/dev/null | grep -v "https://${DOMAIN}/cronbot/" > "$CRON_TMP" || true
  for j in \
    "*/1|croncard" "*/1|NoticationsService" "*/1|sendmessage" "*/1|activeconfig" \
    "*/1|disableconfig" "*/1|iranpay1" "*/2|gift" "*/2|configtest" "*/3|plisio" \
    "*/5|payment_expire" "*/15|statusday" "*/15|on_hold" "*/15|uptime_node" \
    "*/15|uptime_panel" "*/30|expireagent"
  do
    m="${j%%|*}"; f="${j##*|}"
    echo "$m * * * * curl -s https://${DOMAIN}/cronbot/${f}.php >/dev/null 2>&1" >> "$CRON_TMP"
  done
  echo "0 */5 * * * curl -s https://${DOMAIN}/cronbot/backupbot.php >/dev/null 2>&1" >> "$CRON_TMP"
  crontab -u "$CPUSER" "$CRON_TMP" && ok "Cron OK." || warn "Cron fail."
  rm -f "$CRON_TMP"
}

download_mirza_to(){
  local dest="$1" TMP
  TMP="$(mktemp -d)"
  info "Download Mirza..."
  curl -fsSL "$REPO_TAR" -o "$TMP/mirza.tgz" || { rm -rf "$TMP"; bad "Download fail."; return 1; }
  mkdir -p "$dest"
  tar -xzf "$TMP/mirza.tgz" --strip-components=1 -C "$dest" || { rm -rf "$TMP"; bad "Extract fail."; return 1; }
  rm -rf "$TMP"
  ok "Files → $dest"
}

write_config(){
  local CFG="$DOCROOT/config.php"
  [ -f "$CFG" ] || { bad "config.php nist."; return 1; }
  sed -i \
    -e "s|{database_url}|localhost|g" \
    -e "s|{database_name}|${DBNAME}|g" \
    -e "s|{username_db}|${DBUSER}|g" \
    -e "s|{password_db}|${DBPASS}|g" \
    -e "s|{API_KEY}|${BOT_TOKEN}|g" \
    -e "s|{admin_number}|${ADMIN_ID}|g" \
    -e "s|{domain_name}|${DOMAIN}|g" \
    -e "s|{username_bot}|${BOT_USERNAME}|g" \
    "$CFG"
  ok "config.php OK."
}

# patch existing config.php values (token / admin)
cfg_set_php_var(){
  # cfg_set_php_var VARNAME VALUE
  local var="$1" val="$2" cfg="$DOCROOT/config.php"
  [ -f "$cfg" ] || { bad "config.php nist."; return 1; }
  # escape for sed
  local esc; esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
  if grep -qE "^\\\$${var}\s*=" "$cfg"; then
    sed -i -E "s|^(\\\$${var}\s*=\s*')[^']*('.*)$|\1${esc}\2|" "$cfg"
  else
    bad "Variable \$${var} too config peyda nashod."
    return 1
  fi
}

# cPanel often maps subdomain dir under public_html even if UAPI gets a relative path.
resolve_docroot(){
  local ud="/var/cpanel/userdata/${CPUSER}/${DOMAIN}"
  local from_ud=""
  if [ -f "$ud" ]; then
    from_ud="$(awk -F': ' '/^documentroot:/{print $2; exit}' "$ud" 2>/dev/null || true)"
  fi
  if [ -n "$from_ud" ]; then
    DOCROOT="$from_ud"
  elif [ -d "/home/${CPUSER}/public_html/${DOMAIN}" ]; then
    DOCROOT="/home/${CPUSER}/public_html/${DOMAIN}"
  else
    DOCROOT="/home/${CPUSER}/public_html/${DOMAIN}"
  fi
}

create_subdomain(){
  # Prefer public_html path (matches modern cPanel userdata documentroot).
  local REL_DIR="public_html/${DOMAIN}"
  DOCROOT="/home/${CPUSER}/${REL_DIR}"
  info "Subdomain ${DOMAIN} → ${DOCROOT}"

  local OUT
  OUT=$(uapi --user="$CPUSER" SubDomain addsubdomain \
    domain="$SUB" rootdomain="$ROOT_DOMAIN" dir="${REL_DIR}" 2>&1) || true

  if echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
    ok "Subdomain sakhte shod."
  elif echo "$OUT" | grep -qiE 'already exists|exists'; then
    warn "Subdomain ghablan hast — edame."
  else
    # Fallback: legacy dir without public_html prefix (older cPanel)
    OUT=$(uapi --user="$CPUSER" SubDomain addsubdomain \
      domain="$SUB" rootdomain="$ROOT_DOMAIN" dir="${DOMAIN}" 2>&1) || true
    if echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
      ok "Subdomain sakhte shod (legacy dir)."
    elif [ -d "$DOCROOT" ] || [ -d "/home/${CPUSER}/${DOMAIN}" ]; then
      warn "uapi warning — folder/subdomain hast, edame."
    else
      echo "$OUT"
      bad "Subdomain fail. Root domain male in account bashe."
      return 1
    fi
  fi

  resolve_docroot
  mkdir -p "$DOCROOT"
  chown "${CPUSER}:${CPUSER}" "$DOCROOT"
  ok "Docroot: $DOCROOT"
}

mysql_uapi_ok(){
  echo "$1" | grep -Eq 'status:\s*1|"status":1'
}

grant_db_fallback(){
  # When UAPI set_privileges fails, grant as root MySQL.
  mysql -e "CREATE DATABASE IF NOT EXISTS \`${DBNAME}\`;" >/dev/null 2>&1 || true
  mysql -e "CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';" >/dev/null 2>&1 || true
  mysql -e "ALTER USER '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';" >/dev/null 2>&1 || true
  mysql -e "GRANT ALL PRIVILEGES ON \`${DBNAME}\`.* TO '${DBUSER}'@'localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
}

verify_db_login(){
  mysql -u "$DBUSER" -p"$DBPASS" "$DBNAME" -e "SELECT 1;" >/dev/null 2>&1
}

create_database(){
  local raw tag db_short user_short OUT db_try user_try
  raw="$(sanitize "$SUB")"
  tag="$(echo "$raw" | cut -c1-8)"
  [ -n "$tag" ] || tag="b$(date +%s | tail -c 4)"
  db_short="m${tag}"
  user_short="$(echo "u${tag}" | cut -c1-7)"
  DBPASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-18)"

  # Modern cPanel UAPI wants prefixed names (user_db). Older accepted short names.
  DBNAME="${CPUSER}_${db_short}"
  DBUSER="${CPUSER}_${user_short}"

  info "Database (UAPI)..."

  OUT=$(uapi --user="$CPUSER" Mysql create_database name="$DBNAME" 2>&1) || true
  if ! mysql_uapi_ok "$OUT"; then
    OUT=$(uapi --user="$CPUSER" Mysql create_database name="$db_short" 2>&1) || true
    if ! mysql_uapi_ok "$OUT"; then
      # last resort: create as root
      mysql -e "CREATE DATABASE IF NOT EXISTS \`${DBNAME}\`;" >/dev/null 2>&1 || true
      warn "create_database UAPI fail — mysql root fallback."
    fi
  fi

  OUT=$(uapi --user="$CPUSER" Mysql create_user name="$DBUSER" password="$DBPASS" 2>&1) || true
  if ! mysql_uapi_ok "$OUT"; then
    OUT=$(uapi --user="$CPUSER" Mysql create_user name="$user_short" password="$DBPASS" 2>&1) || true
    if ! mysql_uapi_ok "$OUT"; then
      uapi --user="$CPUSER" Mysql set_password user="$DBUSER" password="$DBPASS" >/dev/null 2>&1 || true
      uapi --user="$CPUSER" Mysql set_password user="$user_short" password="$DBPASS" >/dev/null 2>&1 || true
      grant_db_fallback
    else
      uapi --user="$CPUSER" Mysql set_password user="$user_short" password="$DBPASS" >/dev/null 2>&1 || true
    fi
  else
    uapi --user="$CPUSER" Mysql set_password user="$DBUSER" password="$DBPASS" >/dev/null 2>&1 || true
  fi

  OUT=$(uapi --user="$CPUSER" Mysql set_privileges_on_database \
    user="$DBUSER" database="$DBNAME" privileges=ALLPRIVILEGES 2>&1) || true
  if ! mysql_uapi_ok "$OUT"; then
    OUT=$(uapi --user="$CPUSER" Mysql set_privileges_on_database \
      user="$user_short" database="$db_short" privileges=ALLPRIVILEGES 2>&1) || true
  fi
  if ! mysql_uapi_ok "$OUT"; then
    warn "UAPI privilege fail — mysql GRANT fallback."
    grant_db_fallback
  fi

  # Always ensure grants work (covers partial UAPI success)
  grant_db_fallback

  if verify_db_login; then
    ok "DB $DBNAME / $DBUSER"
  else
    bad "DB login fail: $DBUSER @ $DBNAME"
    bad "Check: mysql -u $DBUSER -p'$DBPASS' $DBNAME -e 'SELECT 1;'"
    return 1
  fi
}

verify_web_index(){
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 15 "https://${DOMAIN}/index.php" 2>/dev/null || echo "000")
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
    ok "HTTPS index.php → $code"
    return 0
  fi
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "http://${DOMAIN}/index.php" 2>/dev/null || echo "000")
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
    ok "HTTP index.php → $code"
    return 0
  fi
  warn "index.php HTTP $code — docroot / DNS / SSL check. Expected files in: $DOCROOT"
  return 1
}

# Upstream Mirza 0.2.5: Rebecca panel select crashes (500) because invoice
# query uses code_panel/is_test columns that do not exist. Use Service_location
# like other panel types. Also widen password_panel for API keys / JWT.
patch_mirza_known_bugs(){
  local admin="$DOCROOT/admin.php"
  [ -f "$admin" ] || return 0

  if grep -q 'code_panel = :code_panel AND is_test = 0' "$admin" 2>/dev/null; then
    info "Patch Rebecca invoice SQL (admin.php)..."
    if ! command -v python3 >/dev/null 2>&1; then
      warn "python3 nist — Rebecca patch skip. Dasti fix kon."
    else
      python3 - "$admin" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
old = """    } elseif ($marzban_list_get['type'] == \"rebecca\") {
        $Check_connection = Get_System_Stats_rebecca($marzban_list_get['name_panel']);
        if (empty($Check_connection['error']) && (empty($Check_connection['status']) || $Check_connection['status'] < 400)) {
            $ListSell = $pdo->prepare(\"SELECT COUNT(*) FROM invoice WHERE (status = 'active' OR status = 'end_of_time'  OR status = 'end_of_volume' OR status = 'sendedwarn' OR Status = 'send_on_hold') AND code_panel = :code_panel AND is_test = 0 AND bottype IS NULL\");
            $ListSell->bindParam(':code_panel', $marzban_list_get['code_panel']);
            $ListSell->execute();
            $ListSell = $ListSell->fetch(PDO::FETCH_ASSOC)['COUNT(*)'];
            $ListSellSum = $pdo->prepare(\"SELECT SUM(price_product) FROM invoice WHERE (status = 'active' OR status = 'end_of_time'  OR status = 'end_of_volume' OR status = 'sendedwarn' OR Status = 'send_on_hold') AND code_panel = :code_panel AND is_test = 0 AND bottype IS NULL\");
            $ListSellSum->bindParam(':code_panel', $marzban_list_get['code_panel']);
            $ListSellSum->execute();
            $ListSellSUM = number_format($ListSellSum->fetch(PDO::FETCH_ASSOC)['SUM(price_product)'], 0);
            $text_marzban = sprintf($textbotlang['Admin']['adminphp']['ok_select_panel_user_4'], $ListSell, $ListSellSUM, $marzban_list_get['agent']);
            sendmessage($from_id, $text_marzban, $optionrebecca, 'HTML');"""
new = """    } elseif ($marzban_list_get['type'] == \"rebecca\") {
        $Check_connection = Get_System_Stats_rebecca($marzban_list_get['name_panel']);
        if (empty($Check_connection['error']) && (empty($Check_connection['status']) || $Check_connection['status'] < 400)) {
            $__q_r1 = $pdo->prepare(\"SELECT COUNT(*) FROM invoice WHERE (status = 'active' OR status = 'end_of_time'  OR status = 'end_of_volume' OR status = 'sendedwarn' OR Status = 'send_on_hold') AND Service_location = ? AND name_product != ?\");
            $__q_r1->bindValue(1, $marzban_list_get['name_panel'], PDO::PARAM_STR);
            $__q_r1->bindValue(2, $textbotlang['Admin']['adminphp']['db_test_service_name'], PDO::PARAM_STR);
            $__q_r1->execute();
            $ListSell = number_format($__q_r1->fetch(PDO::FETCH_ASSOC)['COUNT(*)'] ?? 0);
            $__q_r2 = $pdo->prepare(\"SELECT SUM(price_product) FROM invoice WHERE (status = 'active' OR status = 'end_of_time'  OR status = 'end_of_volume' OR status = 'sendedwarn' OR Status = 'send_on_hold') AND Service_location = ? AND name_product != ?\");
            $__q_r2->bindValue(1, $marzban_list_get['name_panel'], PDO::PARAM_STR);
            $__q_r2->bindValue(2, $textbotlang['Admin']['adminphp']['db_test_service_name'], PDO::PARAM_STR);
            $__q_r2->execute();
            $ListSellSUM = number_format($__q_r2->fetch(PDO::FETCH_ASSOC)['SUM(price_product)'] ?? 0);
            $text_marzban = sprintf($textbotlang['Admin']['adminphp']['ok_select_panel_user_4'], $ListSell, $ListSellSUM, $marzban_list_get['agent']);
            sendmessage($from_id, $text_marzban, $optionrebecca, 'HTML');"""
if old not in t:
    print("SKIP: rebecca block pattern not found", file=sys.stderr)
    sys.exit(0)
p.write_text(t.replace(old, new, 1), encoding="utf-8")
print("OK")
PY
      if [ $? -eq 0 ]; then
        ok "Rebecca admin.php patched."
      else
        warn "Rebecca patch fail — dasti check kon."
      fi
    fi
  else
    info "Rebecca invoice SQL already OK (ya pattern nist)."
  fi

  # API keys / JWT often exceed varchar(200)
  if [ -n "${DBNAME:-}" ] && [ -n "${DBUSER:-}" ] && [ -n "${DBPASS:-}" ]; then
    mysql -u "$DBUSER" -p"$DBPASS" "$DBNAME" -e \
      "ALTER TABLE marzban_panel MODIFY password_panel TEXT;" >/dev/null 2>&1 \
      && ok "password_panel → TEXT" \
      || true
  fi
}

update_one_bot(){
  [ -d "$DOCROOT" ] || { bad "Docroot nist: $DOCROOT"; return 1; }
  [ -f "$DOCROOT/config.php" ] || { bad "config.php nist"; return 1; }
  info "Update $DOMAIN ..."
  local TMP CFG_BAK WELL_BAK
  TMP="$(mktemp -d)"
  CFG_BAK="${TMP}/config.php.bak"
  WELL_BAK="${TMP}/well-known"
  cp -a "$DOCROOT/config.php" "$CFG_BAK"
  [ -d "$DOCROOT/.well-known" ] && cp -a "$DOCROOT/.well-known" "$WELL_BAK"
  download_mirza_to "$TMP/new" || { rm -rf "$TMP"; return 1; }
  find "$DOCROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  cp -a "$TMP/new"/. "$DOCROOT"/
  cp -a "$CFG_BAK" "$DOCROOT/config.php"
  [ -d "$WELL_BAK" ] && cp -a "$WELL_BAK" "$DOCROOT/.well-known"
  fix_dirs
  patch_mirza_known_bugs
  run_table_php
  install_crons
  rm -rf "$TMP"
  ok "Updated: $DOMAIN"
}

# ===================== ACTIONS =====================

do_install(){
  need_root || return 1; need_tools || return 1
  ask_account_once || return 1

  echo -e "\n${C_BOLD}==== Install Mirza ====${CR}"
  info "Cloudflare: A record → IP | DNS only (grey)!"
  echo
  read -rp "  Subdomain label (mesl bot1): " SUB
  SUB="$(sanitize "$SUB")"
  [ -n "$SUB" ] || { bad "Khali."; return 1; }
  DOMAIN="${SUB}.${ROOT_DOMAIN}"

  if [ -f "$(bot_meta_path "$DOMAIN")" ]; then
    warn "Ghablan install shode."
    read -rp "  Overwrite files? (y/n): " yn
    [ "$yn" = "y" ] || return 1
  fi

  read -rp "  Token bot: " BOT_TOKEN
  [ -n "${BOT_TOKEN}" ] || { bad "Token khali."; return 1; }
  read -rp "  Username bot bedun @: " BOT_USERNAME
  BOT_USERNAME="${BOT_USERNAME#@}"
  [ -n "${BOT_USERNAME}" ] || { bad "Username khali."; return 1; }
  read -rp "  Admin chat ID: " ADMIN_ID
  [ -n "${ADMIN_ID}" ] || { bad "Admin khali."; return 1; }
  read -rp "  Email [${CPUSER}@${ROOT_DOMAIN}]: " EMAIL
  EMAIL="${EMAIL:-${CPUSER}@${ROOT_DOMAIN}}"

  echo
  info "→ https://${DOMAIN}"
  read -rp "  Edame? (y/n): " yn
  [ "$yn" = "y" ] || return 1

  create_subdomain || return 1
  create_database || return 1
  set_php
  resolve_docroot
  find "$DOCROOT" -mindepth 1 -maxdepth 1 ! -name '.well-known' -exec rm -rf {} + 2>/dev/null || true
  download_mirza_to "$DOCROOT" || return 1
  write_config || return 1
  fix_dirs
  patch_mirza_known_bugs
  run_table_php
  wait_ssl
  verify_web_index || warn "Webhook shayad 404 bede — docroot/DNS check."
  set_webhook
  install_crons
  save_bot_meta

  echo -e "\n${C_OK}======== DONE ========${CR}"
  echo -e "  Bot    : https://${DOMAIN}"
  echo -e "  Admin  : https://${DOMAIN}/admin.php"
  echo -e "  Docroot: ${DOCROOT}"
  echo -e "  DB     : ${DBNAME} / ${DBUSER}"
  echo -e "  Pass   : ${DBPASS}"
  echo -e "  Secrets: ${CREDS_FILE}"
  echo -e "  Telegram: /start → @${BOT_USERNAME}\n"
}

do_list(){
  need_root || return 1; ensure_meta; load_account
  echo
  local d f
  if [ -z "$(list_bot_domains)" ]; then
    warn "Hich bot-i nist."
    return 0
  fi
  while IFS= read -r d; do
    # shellcheck disable=SC1090
    source "$(bot_meta_path "$d")"
    echo -e "  ${C_OK}●${CR} ${C_BOLD}${DOMAIN}${CR}"
    echo -e "      bot   : @${BOT_USERNAME}"
    echo -e "      admin : ${ADMIN_ID}"
    echo -e "      db    : ${DBNAME}"
    echo -e "      path  : ${C_DIM}${DOCROOT}${CR}"
  done < <(list_bot_domains)
  echo
}

do_info(){
  need_root || return 1
  pick_bot || return 1
  echo
  echo -e "  ${C_BOLD}${DOMAIN}${CR}"
  echo -e "  Bot URL     : https://${DOMAIN}"
  echo -e "  Admin panel : https://${DOMAIN}/admin.php"
  echo -e "  Docroot     : ${DOCROOT}"
  echo -e "  DB name     : ${DBNAME}"
  echo -e "  DB user     : ${DBUSER}"
  echo -e "  DB pass     : ${DBPASS}"
  echo -e "  Token       : ${BOT_TOKEN}"
  echo -e "  Username    : @${BOT_USERNAME}"
  echo -e "  Admin ID    : ${ADMIN_ID}"
  echo
  info "Webhook info:"
  curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo" | head -c 500
  echo -e "\n"
}

do_phpmyadmin(){
  need_root || return 1
  pick_bot || return 1
  load_account
  local host cpanel_url
  host="$(hostname -f 2>/dev/null || hostname)"
  cpanel_url="https://${host}:2083"
  # agar domain account-e original hast, oonam moshabehe
  echo
  echo -e "  ${C_BOLD}phpMyAdmin / DB access${CR}"
  echo -e "  -----------------------------------------"
  echo -e "  cPanel login : ${C_INFO}${cpanel_url}${CR}"
  echo -e "                ya  https://${ROOT_DOMAIN:-$host}:2083"
  echo -e "  Username     : ${CPUSER}"
  echo -e "  Az cPanel →   Databases → phpMyAdmin"
  echo -e "  -----------------------------------------"
  echo -e "  Database     : ${C_OK}${DBNAME}${CR}"
  echo -e "  DB user      : ${DBUSER}"
  echo -e "  DB password  : ${DBPASS}"
  echo -e "  -----------------------------------------"
  echo -e "  ${C_DIM}Tip: baraye import backup, too phpMyAdmin"
  echo -e "  Import tab → file .sql ro select kon.${CR}"
  echo
  # optional: get temporary session URL if possible
  if command -v whmapi1 >/dev/null 2>&1; then
    local SSO
    SSO=$(whmapi1 create_user_session user="$CPUSER" service=cpaneld 2>/dev/null | awk '/url:/ {print $2; exit}')
    if [ -n "${SSO:-}" ]; then
      echo -e "  ${C_WARN}One-time cPanel login link:${CR}"
      echo -e "  ${SSO}"
      echo -e "  ${C_DIM}(bad az login → phpMyAdmin)${CR}\n"
    fi
  fi
}

do_restore(){
  need_root || return 1; need_tools || return 1
  echo -e "\n${C_BOLD}==== Restore backup SQL ====${CR}"
  info "Bot jadid bayad ghablan install shode bashe (hamun token ghadimi behtar-e)."
  pick_bot || return 1

  read -rp "  Path-e .sql rooye server: " SQLFILE
  [ -f "$SQLFILE" ] || { bad "File nist: $SQLFILE"; return 1; }

  warn "Import → DB ${DBNAME}"
  read -rp "  Edame? (y/n): " yn
  [ "$yn" = "y" ] || return 1

  mysql "$DBNAME" -e "SET FOREIGN_KEY_CHECKS=0;" >/dev/null 2>&1 || true
  if mysql "$DBNAME" < "$SQLFILE"; then
    ok "Import OK."
  else
    bad "Import fail."
    return 1
  fi
  mysql "$DBNAME" -e "SET FOREIGN_KEY_CHECKS=1;" >/dev/null 2>&1 || true

  set_webhook
  run_table_php

  echo
  warn "Ba'd az restore:"
  echo "    1) Admin panel → domain / sub-link ha → ${DOMAIN}"
  echo "    2) Payment callback URL ha"
  echo "    3) Telegram /start"
  echo
}

do_update(){
  need_root || return 1; need_tools || return 1
  echo -e "\n${C_BOLD}==== Update ====${CR}"
  warn "config.php + DB data mimunan."
  pick_bot || return 1
  read -rp "  Update ${DOMAIN}? (y/n): " yn
  [ "$yn" = "y" ] || return 1
  update_one_bot
}

do_update_all(){
  need_root || return 1; need_tools || return 1
  echo -e "\n${C_BOLD}==== Update ALL ====${CR}"
  [ -n "$(list_bot_domains)" ] || { bad "Bot nist."; return 1; }
  read -rp "  Hame update shan? (y/n): " yn
  [ "$yn" = "y" ] || return 1
  local d
  while IFS= read -r d; do
    DOMAIN="$d"
    load_bot_meta "$DOMAIN" || continue
    update_one_bot || warn "Fail: $DOMAIN"
  done < <(list_bot_domains)
  ok "update-all done."
}

do_set_token(){
  need_root || return 1
  pick_bot || return 1
  echo
  info "Token alan: ${BOT_TOKEN}"
  read -rp "  Token jadid: " NEW_TOKEN
  [ -n "$NEW_TOKEN" ] || { bad "Khali."; return 1; }

  BOT_TOKEN="$NEW_TOKEN"
  cfg_set_php_var "APIKEY" "$BOT_TOKEN" || return 1
  save_bot_meta
  set_webhook
  ok "Token avaz shod."
}

do_set_admin(){
  need_root || return 1
  pick_bot || return 1
  echo
  info "Admin ID alan: ${ADMIN_ID}"
  read -rp "  Admin ID jadid: " NEW_ADMIN
  [ -n "$NEW_ADMIN" ] || { bad "Khali."; return 1; }

  ADMIN_ID="$NEW_ADMIN"
  cfg_set_php_var "adminnumber" "$ADMIN_ID" || return 1
  save_bot_meta
  ok "Admin ID avaz shod → ${ADMIN_ID}"
}

do_webhook(){
  need_root || return 1
  pick_bot || return 1
  set_webhook
  curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo"
  echo
}

do_backup_db(){
  need_root || return 1
  pick_bot || return 1
  local out
  out="/root/${DOMAIN}-$(date +%Y%m%d-%H%M%S).sql"
  info "Dump → $out"
  if mysqldump "$DBNAME" > "$out"; then
    ok "Backup: $out"
    ls -lh "$out"
  else
    bad "mysqldump fail."
  fi
}

remove_bot_crons(){
  local CRON_TMP
  CRON_TMP="$(mktemp)"
  crontab -u "$CPUSER" -l 2>/dev/null | grep -v "https://${DOMAIN}/cronbot/" > "$CRON_TMP" || true
  if [ -s "$CRON_TMP" ]; then
    crontab -u "$CPUSER" "$CRON_TMP" && ok "Cron lines remove shod." || warn "Cron update fail."
  else
    crontab -u "$CPUSER" -r 2>/dev/null || true
    ok "Cron khali / remove shod."
  fi
  rm -f "$CRON_TMP"
}

delete_webhook(){
  [ -n "${BOT_TOKEN:-}" ] || return 0
  info "Webhook delete..."
  local WH
  WH=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/deleteWebhook?drop_pending_updates=true")
  if echo "$WH" | grep -q '"ok":true'; then
    ok "Webhook hazf shod."
  else
    warn "Webhook: $WH"
  fi
}

drop_bot_database(){
  local short_db short_user OUT
  [ -n "${DBNAME:-}" ] || return 0
  info "Drop DB ${DBNAME} / ${DBUSER}..."

  short_db="${DBNAME#${CPUSER}_}"
  short_user="${DBUSER#${CPUSER}_}"

  OUT=$(uapi --user="$CPUSER" Mysql delete_database name="$DBNAME" 2>&1) || true
  if ! echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
    uapi --user="$CPUSER" Mysql delete_database name="$short_db" >/dev/null 2>&1 || true
    mysql -e "DROP DATABASE IF EXISTS \`${DBNAME}\`;" >/dev/null 2>&1 || true
  fi

  if [ -n "${DBUSER:-}" ]; then
    OUT=$(uapi --user="$CPUSER" Mysql delete_user name="$DBUSER" 2>&1) || true
    if ! echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
      uapi --user="$CPUSER" Mysql delete_user name="$short_user" >/dev/null 2>&1 || true
      mysql -e "DROP USER IF EXISTS '${DBUSER}'@'localhost';" >/dev/null 2>&1 || true
      mysql -e "DROP USER IF EXISTS '${DBUSER}'@'%';" >/dev/null 2>&1 || true
      mysql -e "FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
    fi
  fi
  ok "Database remove shod (ya try shod)."
}

delete_bot_subdomain(){
  local OUT sub_label
  info "Subdomain delete..."
  # Full FQDN usually works on modern cPanel
  OUT=$(uapi --user="$CPUSER" SubDomain delsubdomain domain="$DOMAIN" 2>&1) || true
  if echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
    ok "Subdomain hazf shod."
    return 0
  fi
  sub_label="${SUB:-${DOMAIN%%.*}}"
  OUT=$(uapi --user="$CPUSER" SubDomain delsubdomain domain="$sub_label" 2>&1) || true
  if echo "$OUT" | grep -Eq 'status:\s*1|"status":1'; then
    ok "Subdomain hazf shod."
  else
    warn "Subdomain UAPI fail — dasti az cPanel → Domains hazf kon."
    echo "$OUT" | head -20
  fi
}

do_uninstall(){
  need_root || return 1; need_tools || return 1
  echo -e "\n${C_BOLD}==== Uninstall Mirza bot ====${CR}"
  warn "In kar: webhook, cron, files, DB, subdomain, meta ro hazf mikone."
  pick_bot || return 1
  load_account

  echo
  echo -e "  Domain  : ${C_BOLD}${DOMAIN}${CR}"
  echo -e "  Docroot : ${DOCROOT}"
  echo -e "  DB      : ${DBNAME} / ${DBUSER}"
  echo -e "  Bot     : @${BOT_USERNAME}"
  echo
  read -rp "  Backup DB ghabl az hazf? (y/n) [y]: " do_bak
  do_bak="${do_bak:-y}"
  if [ "$do_bak" = "y" ] || [ "$do_bak" = "Y" ]; then
    local out
    out="/root/${DOMAIN}-before-uninstall-$(date +%Y%m%d-%H%M%S).sql"
    if mysqldump "$DBNAME" > "$out" 2>/dev/null; then
      ok "Backup: $out"
    else
      warn "Backup fail (DB shayad nist) — edame."
    fi
  fi

  echo
  warn "Hazf PAYANI. Barghasht nadare (be joz backup)."
  read -rp "  Type exact domain to confirm (${DOMAIN}): " confirm
  [ "$confirm" = "$DOMAIN" ] || { bad "Confirm eshtebah — cancel."; return 1; }

  delete_webhook
  remove_bot_crons
  drop_bot_database

  info "Files..."
  if [ -n "${DOCROOT:-}" ] && [ -d "$DOCROOT" ]; then
    rm -rf "$DOCROOT"
    ok "Removed: $DOCROOT"
  fi
  # legacy path (v1.1 bug)
  if [ -d "/home/${CPUSER}/${DOMAIN}" ]; then
    rm -rf "/home/${CPUSER}/${DOMAIN}"
    ok "Removed legacy: /home/${CPUSER}/${DOMAIN}"
  fi

  delete_bot_subdomain

  local meta
  meta="$(bot_meta_path "$DOMAIN")"
  if [ -f "$meta" ]; then
    rm -f "$meta"
    ok "Meta remove: $meta"
  fi

  echo
  ok "Uninstall DONE: ${DOMAIN}"
  warn "Cloudflare A record (${SUB:-bot}) ro dasti hazf kon age digar lazem nist."
  echo
}

do_self_install(){
  need_root || return 1
  local src
  src="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
  cp -f "$src" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  ok "CLI nasb shod: ${BIN_PATH}"
  info "Az alan:  mirza"
}

show_help(){
cat <<EOF

  ${C_BOLD}mirza${CR}  v${VERSION}  —  cPanel multi-bot CLI

  Commands:
    ${C_OK}install${CR}       Nasb bot jadid (subdomain)
    ${C_OK}uninstall${CR}     Hazf kamel yek bot
    ${C_OK}list${CR}          List bot ha
    ${C_OK}info${CR}          Joziyat yek bot
    ${C_OK}update${CR}        Update code-e yek bot
    ${C_OK}update-all${CR}    Update hame bot ha
    ${C_OK}restore${CR}       Import backup .sql
    ${C_OK}backup${CR}        Export DB → /root/*.sql
    ${C_OK}phpmyadmin${CR}    Link cPanel + DB info
    ${C_OK}set-token${CR}     Avaz kardan token
    ${C_OK}set-admin${CR}     Avaz kardan admin ID
    ${C_OK}webhook${CR}       Set/check webhook
    ${C_OK}setup-cli${CR}     Nasb 'mirza' too /usr/local/bin
    ${C_OK}steps${CR}         Rahnama
    ${C_OK}help${CR}          In help
    ${C_OK}exit${CR}          Khoruj

EOF
}

show_steps(){
cat <<'TXT'

  ============== STEPS ==============

  1) Cloudflare (har bot):
       A record: bot1 → IP VPS
       Abr = DNS only (KHKESTARI)

  2) Nasb CLI:
       curl -fsSL https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh | bash -s -- setup-cli
       mirza

  3) Dakhel CLI:
       mirza> install
       mirza> uninstall
       mirza> list
       mirza> phpmyadmin
       mirza> restore
       mirza> set-token
       mirza> set-admin
       mirza> update
       mirza> update-all

  4) Restore backup:
       - aval install ba hamun token
       - ya file .sql ro upload kon
       - mirza> restore
       - ya phpmyadmin → Import

  ===================================

TXT
}

run_cmd(){
  local c="${1:-}"
  case "$c" in
    install)     do_install ;;
    uninstall|remove|delete) do_uninstall ;;
    list|ls)     do_list ;;
    info|show)   do_info ;;
    update)      do_update ;;
    update-all)  do_update_all ;;
    restore)     do_restore ;;
    backup)      do_backup_db ;;
    phpmyadmin|pma|db) do_phpmyadmin ;;
    set-token|token)   do_set_token ;;
    set-admin|admin)   do_set_admin ;;
    webhook)     do_webhook ;;
    setup-cli|self-install) do_self_install ;;
    steps|guide) show_steps ;;
    help|h|\?)   show_help ;;
    exit|quit|q) echo "  bye."; exit 0 ;;
    "") ;;
    *) bad "Command nashenas: $c  (help bezan)" ;;
  esac
}

repl(){
  need_root || exit 1
  ensure_meta
  echo -e "\n${C_INFO}${C_BOLD}  Mirza cPanel CLI${CR}  v${VERSION}"
  echo -e "  ${C_DIM}help | install | uninstall | update | restore | phpmyadmin | set-token | set-admin | exit${CR}\n"
  local line
  while true; do
    # readline if available
    if ! read -rp "mirza> " line; then
      echo; break
    fi
    # trim
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    run_cmd $line
  done
}

# ---------- entry ----------
ARG="${1:-}"
case "$ARG" in
  ""|shell|cli|menu|repl)
    repl
    ;;
  setup-cli|self-install)
    # support: curl ... | bash -s -- setup-cli
    # when piped, BASH_SOURCE may be empty — write from stdin already consumed; handle install differently
    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
      do_self_install
    else
      bad "Baraye setup-cli file ro download kon, bad ejra kon:"
      echo "  curl -fsSL https://raw.githubusercontent.com/lilezza/mirza-cpanel/main/mirza-cpanel.sh -o /usr/local/bin/mirza && chmod +x /usr/local/bin/mirza && mirza"
      exit 1
    fi
    ;;
  *)
    run_cmd "$@"
    ;;
esac
