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

# S'assurer que l'admin a les bonnes permissions WC
# On fait TOUT en PHP direct (pas WP-CLI) car wp user add-cap échoue silencieusement au boot
cat > /tmp/fix-wc-caps.php <<'FIXCAPS'
<?php
define('ABSPATH', '/var/www/html/');
define('WPINC', 'wp-includes');
if (file_exists(ABSPATH . 'wp-load.php')) {
    require_once ABSPATH . 'wp-load.php';
    $user = new WP_User(1);
    // Ajouter le rôle shop_manager (inclut manage_woocommerce)
    $user->add_role('shop_manager');
    // Ajouter les caps individuelles aussi (backup)
    $user->add_cap('manage_woocommerce');
    $user->add_cap('edit_products');
    $user->add_cap('publish_products');
    $user->add_cap('edit_others_products');
    $user->add_cap('read_private_products');
    $user->add_cap('list_users');
    echo "WC caps added for user 1. Caps: " . json_encode(array_keys($user->allcaps)) . "\n";
} else {
    echo "ERROR: wp-load.php not found\n";
}
FIXCAPS
php /tmp/fix-wc-caps.php 2>&1 || true

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API REST — TOUT en bash + MySQL CLI (pas de PHP)
# ══════════════════════════════════════════════════════════════════════════════

log "[5/5] Clés API REST..."

# WooCommerce auth: consumer_key est hashé avec hash_hmac('sha256', key, 'wc-api')
# consumer_secret stocké EN CLAIR en DB
# Voir: wc_api_hash() dans wc-core-functions.php

CK_RAW=""
CS_RAW=""

# Méthode 0: Réutiliser les clés existantes en DB (si déjà en boot précédent)
EXISTING_KEYS=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -N -e \
    "SELECT COUNT(*) FROM wp_woocommerce_api_keys" 2>/dev/null || echo "0")
log "  → Existing keys in DB: $EXISTING_KEYS"

if [ "$EXISTING_KEYS" != "0" ]; then
    log "  → Keys already exist, using existing ones"
    # On ne peut pas récupérer les clés en clair (le consumer_key est hashé)
    # Donc on lit le JSON existant
    if [ -f "$WP_DIR/wc-api-keys.json" ]; then
        CK_RAW=$(python3 -c "import json; d=json.load(open('$WP_DIR/wc-api-keys.json')); print(d.get('consumer_key',''))" 2>/dev/null || echo "")
        CS_RAW=$(python3 -c "import json; d=json.load(open('$WP_DIR/wc-api-keys.json')); print(d.get('consumer_secret',''))" 2>/dev/null || echo "")
    fi
fi

# Méthode 1: PHP $wpdb (pas mysql CLI qui échoue silencieusement)
if [ -z "$CK_RAW" ] || [ -z "$CS_RAW" ]; then
    log "  → Generating new keys via PHP..."
    CK_RAW="ck_$(head -c 40 /dev/urandom | od -A n -t x1 | tr -d ' \n' | head -c 40)"
    CS_RAW="cs_$(head -c 40 /dev/urandom | od -A n -t x1 | tr -d ' \n' | head -c 40)"
    CK_HASHED=$(echo -n "$CK_RAW" | openssl dgst -sha256 -hmac "wc-api" | awk '{print $2}')

    php -r "
    define('ABSPATH', '/var/www/html/');
    require_once ABSPATH . 'wp-load.php';
    global \$wpdb;
    \$wpdb->delete(\$wpdb->prefix . 'woocommerce_api_keys');
    \$wpdb->insert(\$wpdb->prefix . 'woocommerce_api_keys', array(
        'user_id' => 1,
        'description' => 'OLMEICK Bridge',
        'permissions' => 'read_write',
        'consumer_key' => '$CK_HASHED',
        'consumer_secret' => '$CS_RAW',
        'nonces' => ''
    ));
    if (\$wpdb->insert_id > 0) {
        echo 'OK';
    } else {
        echo 'ERROR: ' . \$wpdb->last_error;
    }
    " 2>&1
fi

log "  → Consumer Key: $CK_RAW"

# Vérifier les clés en DB
DB_KEYS=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce -N -e "SELECT COUNT(*) FROM wp_woocommerce_api_keys" 2>/dev/null || echo "0")
log "  → Keys in DB: $DB_KEYS"

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
TEST_AUTH=$(curl -s --max-time 15 "https://olmeick-woocommerce.onrender.com/wp-json/wc/v3/products?consumer_key=$CK_RAW&consumer_secret=$CS_RAW&per_page=1" 2>/dev/null | head -c 200)
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
# debug.php — diagnostic endpoint (supprimer en prod)
# ══════════════════════════════════════════════════════════════════════════════

cat > "$WP_DIR/debug.php" <<'DEBUG_PHP'
<?php
header('Content-Type: application/json');
error_reporting(E_ALL);
ini_set('display_errors', 0);

$result = array();

// 1. Check if WP loaded
$result['wp_loaded'] = defined('ABSPATH');

// 2. Load WP
if (!function_exists('get_userdata')) {
    define('ABSPATH', dirname(__FILE__) . '/');
    define('WPINC', 'wp-includes');
    @require_once ABSPATH . 'wp-load.php';
}
$result['wp_functions'] = function_exists('get_userdata');

// 3. Get user 1 data
$user = get_userdata(1);
if ($user) {
    $result['user_id'] = 1;
    $result['user_login'] = $user->user_login;
    $result['user_email'] = $user->user_email;
    $result['roles'] = $user->roles;
    $result['allcaps'] = array_keys($user->allcaps);
    $result['has_manage_woocommerce'] = $user->has_cap('manage_woocommerce');
    $result['has_edit_products'] = $user->has_cap('edit_products');
    $result['has_read'] = $user->has_cap('read');
} else {
    $result['error'] = 'User ID 1 not found!';
}

// 4. Check WC tables
global $wpdb;
$tables = $wpdb->get_col("SHOW TABLES LIKE '%woocommerce%'", 0);
$result['wc_tables'] = $tables;

// 5. Check API keys count
$keys = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}woocommerce_api_keys");
$result['api_keys_count'] = $keys;

// 6. Check WC options
$wc_active = $wpdb->get_var("SELECT option_value FROM {$wpdb->prefix}options WHERE option_name = 'active_plugins'");
$result['active_plugins'] = $wc_active;

// 7. Plugin file exists
$result['wc_plugin_exists'] = file_exists(ABSPATH . 'wp-content/plugins/woocommerce/woocommerce.php');

// 8. Shop manager role exists
$role = get_role('shop_manager');
$result['shop_manager_role_exists'] = ($role !== null);

// 9. Simulate WC REST auth flow
if (isset($_GET['ck']) && isset($_GET['cs'])) {
    $ck = sanitize_text_field($_GET['ck']);
    $cs = $_GET['cs'];
    if (function_exists('wc_api_hash')) {
        $result['wc_api_hash_exists'] = true;
        $hashed = wc_api_hash($ck);
        $result['ck_hash'] = $hashed;
        $row = $wpdb->get_row($wpdb->prepare(
            "SELECT * FROM {$wpdb->prefix}woocommerce_api_keys WHERE consumer_key = %s", $hashed
        ));
        $result['db_lookup_found'] = ($row !== null);
        if ($row) {
            $result['row_user_id'] = (int)$row->user_id;
            $result['row_permissions'] = $row->permissions;
            $result['secret_match'] = hash_equals($row->consumer_secret, $cs);
            $user2 = get_user_by('ID', $row->user_id);
            if ($user2) {
                wp_set_current_user($user2->ID);
                $result['current_user_id'] = get_current_user_id();
                $result['can_edit_posts'] = current_user_can('edit_posts');
                $result['can_read'] = current_user_can('read');
                $result['can_manage_woocommerce'] = current_user_can('manage_woocommerce');
            }
        }
    } else {
        $result['wc_api_hash_exists'] = false;
    }
}

// 10. Count all DB rows
$all_keys = $wpdb->get_results("SELECT key_id, user_id, consumer_key, permissions FROM {$wpdb->prefix}woocommerce_api_keys");
$result['all_keys'] = array_map(function($k) {
    return array('key_id' => $k->key_id, 'user_id' => $k->user_id, 'consumer_key' => substr($k->consumer_key, 0, 20) . '...', 'permissions' => $k->permissions);
}, $all_keys);

// FIX MODE: ?fix=1 — crée les clés API via $wpdb (bypass les problèmes bash/MySQL)
if (isset($_GET['fix']) && $_GET['fix'] === '1') {
    $result['fix_mode'] = true;
    
    // Supprimer les anciennes clés
    $wpdb->query("DELETE FROM {$wpdb->prefix}woocommerce_api_keys");
    
    // Générer les clés
    $ck = 'ck_' . bin2hex(random_bytes(20));
    $cs = 'cs_' . bin2hex(random_bytes(20));
    $ck_hashed = hash_hmac('sha256', $ck, 'wc-api');
    // Insert via $wpdb (WordPress DB layer)
    $inserted = $wpdb->insert(
        $wpdb->prefix . 'woocommerce_api_keys',
        array(
            'user_id' => 1,
            'description' => 'OLMEICK Bridge',
            'permissions' => 'read_write',
            'consumer_key' => $ck_hashed,
            'consumer_secret' => $cs,
            'nonces' => '',
        ),
        array('%d', '%s', '%s', '%s', '%s', '%s')
    );
    
    $result['insert_result'] = $inserted;
    $result['insert_error'] = $wpdb->last_error;
    $result['new_ck'] = $ck;
    $result['new_cs'] = $cs;
    $result['new_ck_hash'] = $ck_hashed;
    
    // Vérifier
    $count = $wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->prefix}woocommerce_api_keys");
    $result['new_count'] = $count;
    
    // Sauvegarder en JSON aussi
    $json_data = array(
        'consumer_key' => $ck,
        'consumer_secret' => $cs,
        'store_url' => 'https://olmeick-woocommerce.onrender.com'
    );
    file_put_contents('/var/www/html/wc-api-keys.json', json_encode($json_data, JSON_PRETTY_PRINT));
    
    // Test auth immédiat
    $row = $wpdb->get_row($wpdb->prepare(
        "SELECT * FROM {$wpdb->prefix}woocommerce_api_keys WHERE consumer_key = %s",
        $ck_hashed
    ));
    $result['auth_test'] = array(
        'found_in_db' => ($row !== null),
        'secret_match' => $row ? hash_equals($row->consumer_secret, $cs) : false,
    );
    
    if ($row) {
        wp_set_current_user((int)$row->user_id);
        $result['auth_test']['current_user_id'] = get_current_user_id();
        $result['auth_test']['can_edit_posts'] = current_user_can('edit_posts');
        $result['auth_test']['can_manage_woocommerce'] = current_user_can('manage_woocommerce');
    }
    
    // Test API REST immédiat (depuis le serveur lui-même)
    $test_url = 'https://olmeick-woocommerce.onrender.com/wp-json/wc/v3/products?consumer_key=' . urlencode($ck) . '&consumer_secret=' . urlencode($cs) . '&per_page=1';
    $response = @wp_remote_get($test_url, array('timeout' => 10));
    if (is_wp_error($response)) {
        $result['rest_test'] = $response->get_error_message();
    } else {
        $result['rest_test_status'] = wp_remote_retrieve_response_code($response);
        $result['rest_test_body'] = substr(wp_remote_retrieve_body($response), 0, 300);
    }
}

echo json_encode($result, JSON_PRETTY_PRINT);
DEBUG_PHP
chmod 644 "$WP_DIR/debug.php"

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
RewriteRule ^debug\.php$ - [L]
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
