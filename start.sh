#!/bin/bash
# OLMEICK WooCommerce Bridge - Script de demarrage
# Optimise pour Render Free Tier (512MB RAM, stockage ephemere)

WP_DIR="/var/www/html"
MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
WC_FLAG="$WP_DIR/.wc-installed"
API_KEY_FLAG="$WP_DIR/.api-keys-created"
HTTP_PORT="${PORT:-8080}"
LOG_PREFIX="[OLMEICK]"

log() { echo "$LOG_PREFIX $1"; }
err() { echo "$LOG_PREFIX ❌ $1" >&2; }

log "========================================="
log "  OLMEICK WooCommerce Bridge"
log "  Port: $HTTP_PORT"
log "========================================="

# ══════════════════════════════════════════════════════════════════════════════
# HEALTH CHECK
# ══════════════════════════════════════════════════════════════════════════════

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
    if [ -d /var/lib/mysql/mysql ] && [ ! -S "$MYSQL_SOCKET" ]; then
        rm -rf /var/lib/mysql/*
    fi
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    { err "MariaDB init failed"; exit 1; }

    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --socket="$MYSQL_SOCKET" --pid-file="$MYSQL_SOCKET.pid" --innodb-buffer-pool-size=16M --key-buffer-size=8M &
    MYSQL_READY=0
    for i in $(seq 1 45); do
        if [ -S "$MYSQL_SOCKET" ]; then
            if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then MYSQL_READY=1; break; fi
        fi
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
    log "  → Init OK"
fi

mysqld --user=mysql --datadir=/var/lib/mysql --socket="$MYSQL_SOCKET" --pid-file="$MYSQL_SOCKET.pid" --skip-name-resolve --innodb-buffer-pool-size=32M --key-buffer-size=16M --max-allowed-packet=8M --tmp-table-size=8M --max-heap-table-size=8M --table-open-cache=32 --sort-buffer-size=128K --read-buffer-size=128K --thread-cache-size=2 &

MYSQL_READY=0
for i in $(seq 1 45); do
    if [ -S "$MYSQL_SOCKET" ]; then
        if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then MYSQL_READY=1; break; fi
    fi
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

DB_TEST=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='woocommerce'" -N 2>/dev/null || echo "FAIL")
log "  → Tables: $DB_TEST"

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress
# ══════════════════════════════════════════════════════════════════════════════

log "[2/5] WordPress..."

if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    log "  → Downloading WordPress..."
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
fi

rm -f "$WP_DIR/wp-config.php"
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

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

log "  → wp-config.php OK"

# ══════════════════════════════════════════════════════════════════════════════
# 3. wp core install
# ══════════════════════════════════════════════════════════════════════════════

log "[3/5] WordPress install..."
if ! wp core is-installed --path="$WP_DIR" --allow-root 2>/dev/null; then
    wp core install --url="https://olmeick-woocommerce.onrender.com" --title="OLMEICK Bridge" --admin_user=admin --admin_password=OLMEICK_admin_2026 --admin_email=bridge@olmeick.com --path="$WP_DIR" --allow-root 2>&1 || log "  → WP install warn"
fi
log "  → WP installed"

# ══════════════════════════════════════════════════════════════════════════════
# 4. WooCommerce
# ══════════════════════════════════════════════════════════════════════════════

log "[4/5] WooCommerce..."
if [ ! -f "$WC_FLAG" ]; then
    wp plugin install woocommerce --activate --path="$WP_DIR" --allow-root 2>&1 || log "  → WC install warn"
    wp option update woocommerce_store_address "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_store_city "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_default_country "BJ" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_currency "USD" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_calc_taxes "yes" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite structure '/%postname%/' --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite flush --path="$WP_DIR" --allow-root 2>/dev/null || true
    touch "$WC_FLAG"
fi
log "  → WooCommerce OK"

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API + endpoints
# ══════════════════════════════════════════════════════════════════════════════

log "[5/5] API keys + endpoints..."

# api-keys.php — endpoint auto-générant
# Si les clés n'existent pas, il les crée au premier appel
cat > "$WP_DIR/api-keys.php" <<'APIKEYS_PHP'
<?php
error_reporting(0);
header('Content-Type: application/json');

$json_file = '/var/www/html/wc-api-keys.json';
$db_file   = '/var/www/html/.api-keys-created';

// Si les clés existent déjà, les retourner
if (file_exists($json_file)) {
    $data = json_decode(file_get_contents($json_file), true);
    if (!empty($data['consumer_key']) && !empty($data['consumer_secret'])) {
        echo file_get_contents($json_file);
        exit;
    }
}

// Sinon, les générer via MySQL direct
$ck = 'ck_' . bin2hex(random_bytes(20));
$cs = 'cs_' . bin2hex(random_bytes(20));
$ck_hashed = hash_hmac('sha256', $ck, 'wc-api');
$ts = date('Y-m-d H:i:s');

$db = new mysqli('localhost', 'olmeick', 'olmeick_wc_2026', 'woocommerce', 3306, '/var/run/mysqld/mysqld.sock');
if ($db->connect_error) {
    echo json_encode(['error' => 'DB: ' . $db->connect_error]);
    exit;
}

// Supprimer les anciennes clés
$db->query('DELETE FROM wp_woocommerce_api_keys');

// Insérer les nouvelles
$stmt = $db->prepare('INSERT INTO wp_woocommerce_api_keys (user_id, description, permissions, consumer_key, consumer_secret, nonces, date_created) VALUES (?, ?, ?, ?, ?, ?, ?)');
$uid = 1;
$desc = 'OLMEICK Bridge';
$perm = 'read_write';
$nonces = '';
$stmt->bind_param('issssss', $uid, $desc, $perm, $ck_hashed, $cs, $nonces, $ts);
$stmt->execute();
$key_id = $db->insert_id;

if ($key_id > 0) {
    $result = ['consumer_key' => $ck, 'consumer_secret' => $cs, 'store_url' => 'https://olmeick-woocommerce.onrender.com', 'key_id' => $key_id];
    file_put_contents($json_file, json_encode($result));
    chmod($json_file, 0644);
    echo json_encode($result);
} else {
    echo json_encode(['error' => 'Insert failed: ' . $db->error]);
}
APIKEYS_PHP
chmod 644 "$WP_DIR/api-keys.php"

touch "$API_KEY_FLAG"
log "  → api-keys.php OK"

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

# ══════════════════════════════════════════════════════════════════════════════
log "========================================="
log "  OLMEICK WooCommerce Bridge ✅"
log "  MariaDB ✅ | WordPress ✅ | WC ✅"
log "  Port: $HTTP_PORT | Health: /health"
log "  API Keys: /api-keys.php"
log "========================================="

exec apache2-foreground
