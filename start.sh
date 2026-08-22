#!/bin/bash
# OLMEICK WooCommerce Bridge - Script de demarrage
# Optimise pour Render Free Tier (512MB RAM, stockage ephemere)

WP_DIR="/var/www/html"
MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
WC_FLAG="$WP_DIR/.wc-installed"
HTTP_PORT="${PORT:-8080}"
LOG_PREFIX="[OLMEICK]"

log() { echo "$LOG_PREFIX $1"; }
err() { echo "$LOG_PREFIX ❌ $1" >&2; }

log "========================================="
log "  OLMEICK WooCommerce Bridge"
log "  Port: $HTTP_PORT"
log "========================================="

mkdir -p "$WP_DIR"
cat > "$WP_DIR/health" <<'HEALTH'
OK
HEALTH
chmod 644 "$WP_DIR/health"

# ══════════════════════════════════════════════════════════════════════════════
# 1. MariaDB
# ══════════════════════════════════════════════════════════════════════════════

log "[1/5] MariaDB..."

mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld
chmod 755 /var/run/mysqld

if [ ! -d /var/lib/mysql/mysql ] || [ ! -S "$MYSQL_SOCKET" ]; then
    log "  → Init MariaDB..."
    [ -d /var/lib/mysql/mysql ] && rm -rf /var/lib/mysql/*
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    { err "MariaDB init failed"; exit 1; }

    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --socket="$MYSQL_SOCKET" --pid-file="$MYSQL_SOCKET.pid" --innodb-buffer-pool-size=16M --key-buffer-size=8M &
    MYSQL_READY=0
    for i in $(seq 1 45); do
        [ -S "$MYSQL_SOCKET" ] && mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1 && MYSQL_READY=1 && break
        sleep 1
    done
    [ "$MYSQL_READY" -ne 1 ] && { err "MariaDB not ready"; exit 1; }

    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL'
        CREATE DATABASE IF NOT EXISTS woocommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --socket="$MYSQL_SOCKET" -u root shutdown 2>/dev/null || true
    sleep 2
    rm -f "$MYSQL_SOCKET" "$MYSQL_SOCKET.pid"
fi

mysqld --user=mysql --datadir=/var/lib/mysql --socket="$MYSQL_SOCKET" --pid-file="$MYSQL_SOCKET.pid" --skip-name-resolve --innodb-buffer-pool-size=32M --key-buffer-size=16M --max-allowed-packet=8M --tmp-table-size=8M --max-heap-table-size=8M --table-open-cache=32 --sort-buffer-size=128K --read-buffer-size=128K --thread-cache-size=2 &

MYSQL_READY=0
for i in $(seq 1 45); do
    [ -S "$MYSQL_SOCKET" ] && mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1 && MYSQL_READY=1 && break
    sleep 1
done
[ "$MYSQL_READY" -ne 1 ] && { err "MariaDB not started"; exit 1; }
log "  → MariaDB OK"

if ! mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "USE woocommerce" 2>/dev/null; then
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL2'
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOSQL2
fi

log "  → DB tables: $(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='woocommerce'" 2>/dev/null || echo FAIL)"

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress
# ══════════════════════════════════════════════════════════════════════════════

log "[2/5] WordPress..."

if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
fi

KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

cat > "$WP_DIR/wp-config.php" <<'WPCONFIG'
<?php
define('DB_NAME', 'woocommerce');
define('DB_USER', 'olmeick');
define('DB_PASSWORD', 'olmeick_wc_2026');
define('DB_HOST', 'localhost:/var/run/mysqld/mysqld.sock');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', 'utf8mb4_unicode_ci');
WPCONFIG

if [ -n "$KEYS" ]; then
    echo "$KEYS" >> "$WP_DIR/wp-config.php"
else
    cat >> "$WP_DIR/wp-config.php" <<'SALTS'
define('AUTH_KEY',         'OLMEICK-bridge-auth-key-2026!xK9m');
define('SECURE_AUTH_KEY',  'OLMEICK-bridge-secure-auth-2026!pL3n');
define('LOGGED_IN_KEY',    'OLMEICK-bridge-logged-in-2026!jH7v');
define('NONCE_KEY',        'OLMEICK-bridge-nonce-key-2026!wR5t');
define('AUTH_SALT',        'OLMEICK-bridge-auth-salt-2026!mB2q');
define('SECURE_AUTH_SALT', 'OLMEICK-bridge-secure-salt-2026!kN8f');
define('LOGGED_IN_SALT',   'OLMEICK-bridge-logged-salt-2026!dY4s');
define('NONCE_SALT',       'OLMEICK-bridge-nonce-salt-2026!uG6w');
SALTS
fi

cat >> "$WP_DIR/wp-config.php" <<'WPEOF'
$table_prefix = 'wp_';

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('WP_HOME', 'https://olmeick-woocommerce.onrender.com');
define('WP_SITEURL', 'https://olmeick-woocommerce.onrender.com');

if (!defined('ABSPATH')) define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
WPEOF

log "  → wp-config OK"

# ══════════════════════════════════════════════════════════════════════════════
# 3. WordPress install
# ══════════════════════════════════════════════════════════════════════════════

log "[3/5] WP install..."
if ! wp core is-installed --path="$WP_DIR" --allow-root 2>/dev/null; then
    wp core install --url="https://olmeick-woocommerce.onrender.com" --title="OLMEICK Bridge" --admin_user=admin --admin_password=OLMEICK_admin_2026 --admin_email=bridge@olmeick.com --path="$WP_DIR" --allow-root 2>&1
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. WooCommerce
# ══════════════════════════════════════════════════════════════════════════════

log "[4/5] WooCommerce..."
if [ ! -f "$WC_FLAG" ]; then
    wp plugin install woocommerce --activate --path="$WP_DIR" --allow-root 2>&1
    wp option update woocommerce_store_address "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null
    wp option update woocommerce_store_city "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null
    wp option update woocommerce_default_country "BJ" --path="$WP_DIR" --allow-root 2>/dev/null
    wp option update woocommerce_currency "USD" --path="$WP_DIR" --allow-root 2>/dev/null
    wp option update woocommerce_calc_taxes "yes" --path="$WP_DIR" --allow-root 2>/dev/null
    wp rewrite structure '/%postname%/' --path="$WP_DIR" --allow-root 2>/dev/null
    wp rewrite flush --path="$WP_DIR" --allow-root 2>/dev/null
    touch "$WC_FLAG"
fi

# Forcer la création des tables WC (sécurité)
wp wc --version --path="$WP_DIR" --allow-root 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API REST — TOUT en bash + MySQL CLI (pas de PHP)
# ══════════════════════════════════════════════════════════════════════════════

log "[5/5] Clés API REST..."

# WooCommerce hash: hash_hmac('sha256', consumer_key, 'wc-api')
# consumer_secret stocké EN CLAIR en DB

# Générer les clés en bash
CK_RAW="ck_$(head -c 40 /dev/urandom | od -A n -t x1 | tr -d ' \n' | head -c 40)"
CS_RAW="cs_$(head -c 40 /dev/urandom | od -A n -t x1 | tr -d ' \n' | head -c 40)"

# Hasher le consumer_key comme WC le fait
CK_HASHED=$(echo -n "$CK_RAW" | openssl dgst -sha256 -hmac "wc-api" | awk '{print $2}')

log "  → Consumer Key: $CK_RAW"
log "  → Hash: $CK_HASHED"

# Vérifier que la table existe
TABLE_EXISTS=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='wp_woocommerce_api_keys'" 2>/dev/null || echo "0")
log "  → Table wp_woocommerce_api_keys exists: $TABLE_EXISTS"

if [ "$TABLE_EXISTS" = "0" ]; then
    log "  → Creating wp_woocommerce_api_keys table..."
    mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce <<-'CREATE_TABLE'
        CREATE TABLE IF NOT EXISTS wp_woocommerce_api_keys (
            key_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            user_id BIGINT UNSIGNED NOT NULL,
            description VARCHAR(200) NOT NULL,
            permissions VARCHAR(10) NOT NULL,
            consumer_key VARCHAR(64) NOT NULL,
            consumer_secret VARCHAR(255) NOT NULL,
            nonces LONGTEXT,
            last_access DATETIME,
            date_created DATETIME NOT NULL,
            PRIMARY KEY (key_id),
            KEY user_id (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE_TABLE
    log "  → Table created"
fi

# Supprimer les anciennes clés
mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -e "DELETE FROM wp_woocommerce_api_keys" 2>/dev/null || true

# Insérer les nouvelles clés
NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -e \
    "INSERT INTO wp_woocommerce_api_keys (user_id, description, permissions, consumer_key, consumer_secret, nonces, date_created) VALUES (1, 'OLMEICK Bridge', 'read_write', '$CK_HASHED', '$CS_RAW', '', '$NOW')" 2>&1

INSERT_OK=$?
log "  → Insert result: $INSERT_OK"

# Vérifier l'insertion
VERIFY=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -N -e "SELECT COUNT(*) FROM wp_woocommerce_api_keys" 2>/dev/null || echo "0")
log "  → Keys in DB: $VERIFY"

# Sauvegarder dans un fichier JSON
cat > "$WP_DIR/wc-api-keys.json" <<KEYJSON
{
  "consumer_key": "$CK_RAW",
  "consumer_secret": "$CS_RAW",
  "store_url": "https://olmeick-woocommerce.onrender.com"
}
KEYJSON
chmod 644 "$WP_DIR/wc-api-keys.json"
log "  → Saved to /wc-api-keys.json"

# Test de l'auth
TEST_AUTH=$(curl -s --max-time 15 "https://olmeick-woocommerce.onrender.com/wp-json/wc/v3/products?consumer_key=$CK_RAW&consumer_secret=$CS_RAW&per_page=1" 2>/dev/null | head -c 100)
log "  → Auth test: $TEST_AUTH"

# ══════════════════════════════════════════════════════════════════════════════
# api-keys.php endpoint
# ══════════════════════════════════════════════════════════════════════════════

cat > "$WP_DIR/api-keys.php" <<'APIKEYS_PHP'
<?php
header('Content-Type: application/json');
$json_file = '/var/www/html/wc-api-keys.json';
if (file_exists($json_file)) {
    echo file_get_contents($json_file);
} else {
    echo json_encode(array('error' => 'No keys'));
}
APIKEYS_PHP
chmod 644 "$WP_DIR/api-keys.php"

# ══════════════════════════════════════════════════════════════════════════════
# PERMISSIONS + HTACCESS
# ══════════════════════════════════════════════════════════════════════════════

chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php" 2>/dev/null || true
chmod 644 "$WP_DIR/health" 2>/dev/null || true

cat > "$WP_DIR/.htaccess" <<'HTEOF'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^health$ - [L]
RewriteRule ^api-keys\.php$ - [L]
</IfModule>
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
chmod 644 "$WP_DIR/.htaccess"

log "========================================="
log "  OLMEICK WooCommerce Bridge ✅"
log "  MariaDB ✅ | WordPress ✅ | WC ✅"
log "  Port: $HTTP_PORT | Health: /health"
log "========================================="

exec apache2-foreground
