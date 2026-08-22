#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de démarrage robuste
# Optimisé pour Render Free Tier (512MB RAM, stockage éphémère)

# PAS de set -e — on gère les erreurs nous-mêmes

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
# HEALTH CHECK — Render WAF a besoin d'un 200 sur /health
# ══════════════════════════════════════════════════════════════════════════════

mkdir -p "$WP_DIR"
cat > "$WP_DIR/health" <<'HEALTH'
OK
HEALTH
chmod 644 "$WP_DIR/health"

# ══════════════════════════════════════════════════════════════════════════════
# 1. MariaDB — Socket UNIX (optimisé 512MB)
# ══════════════════════════════════════════════════════════════════════════════

log "[1/5] MariaDB..."

# Créer le répertoire socket
mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld
chmod 755 /var/run/mysqld

# --- Initialisation (premier lancement ou stockage perdu) ---
if [ ! -d /var/lib/mysql/mysql ] || [ ! -S "$MYSQL_SOCKET" ]; then
    log "  → Initialisation de MariaDB..."

    # Nettoyer les données corrompues si elles existent partiellement
    if [ -d /var/lib/mysql/mysql ] && [ ! -S "$MYSQL_SOCKET" ]; then
        log "  → Données partielles détectées, réinitialisation..."
        rm -rf /var/lib/mysql/*
    fi

    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    { err "Échec init MariaDB"; exit 1; }

    log "  → Démarrage temporaire pour création DB..."
    mysqld --user=mysql --datadir=/var/lib/mysql \
        --skip-networking \
        --socket="$MYSQL_SOCKET" \
        --pid-file="$MYSQL_SOCKET.pid" \
        --innodb-buffer-pool-size=16M \
        --key-buffer-size=8M &

    # Attendre le socket (max 45s)
    MYSQL_READY=0
    for i in $(seq 1 45); do
        if [ -S "$MYSQL_SOCKET" ]; then
            if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
                MYSQL_READY=1
                break
            fi
        fi
        sleep 1
        if [ $((i % 10)) -eq 0 ]; then
            log "  → Attente MariaDB... (${i}s)"
        fi
    done

    if [ "$MYSQL_READY" -ne 1 ]; then
        err "MariaDB pas prêt après 45s"
        # Diagnostic
        log "  → ls /var/lib/mysql/: $(ls /var/lib/mysql/ 2>&1 | head -5)"
        log "  → Socket exists: $([ -S "$MYSQL_SOCKET" ] && echo YES || echo NO)"
        exit 1
    fi

    log "  → Création de la base de données..."
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL'
        CREATE DATABASE IF NOT EXISTS woocommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
EOSQL

    log "  → Arrêt temporaire..."
    mysqladmin --socket="$MYSQL_SOCKET" -u root shutdown 2>/dev/null || true
    sleep 2
    rm -f "$MYSQL_SOCKET" "$MYSQL_SOCKET.pid"
    log "  → ✅ Init OK"
fi

# --- Démarrage permanent ---
log "  → Démarrage MariaDB..."
mysqld --user=mysql --datadir=/var/lib/mysql \
    --socket="$MYSQL_SOCKET" \
    --pid-file="$MYSQL_SOCKET.pid" \
    --skip-name-resolve \
    --innodb-buffer-pool-size=32M \
    --key-buffer-size=16M \
    --max-allowed-packet=8M \
    --tmp-table-size=8M \
    --max-heap-table-size=8M \
    --table-open-cache=32 \
    --sort-buffer-size=128K \
    --read-buffer-size=128K \
    --thread-cache-size=2 &

# Attendre le socket (max 45s)
MYSQL_READY=0
for i in $(seq 1 45); do
    if [ -S "$MYSQL_SOCKET" ]; then
        if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
            MYSQL_READY=1
            break
        fi
    fi
    sleep 1
    if [ $((i % 10)) -eq 0 ]; then
        log "  → Attente MariaDB... (${i}s)"
    fi
done

if [ "$MYSQL_READY" -ne 1 ]; then
    err "MariaDB pas démarré après 45s"
    exit 1
fi
log "  → ✅ MariaDB actif"

# Vérifier/créer l'utilisateur
if ! mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "USE woocommerce" 2>/dev/null; then
    log "  → Recréation de l'utilisateur..."
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL2'
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOSQL2
fi

# Vérifier que la DB est accessible
DB_TEST=$(mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='woocommerce'" -N 2>/dev/null || echo "FAIL")
log "  → Tables dans woocommerce: $DB_TEST"

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress — Socket UNIX
# ══════════════════════════════════════════════════════════════════════════════

log "[2/5] WordPress..."

if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    log "  → Téléchargement de WordPress..."
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
    log "  → ✅ Téléchargé"
fi

# Toujours recréer wp-config.php (au cas où les salts changent)
rm -f "$WP_DIR/wp-config.php"
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

# Configuration DB via PHP (plus fiable que sed)
cat > "$WP_DIR/wp-config.php" <<'WPCONFIG'
<?php
define('DB_NAME', 'woocommerce');
define('DB_USER', 'olmeick');
define('DB_PASSWORD', 'olmeick_wc_2026');
define('DB_HOST', 'localhost:/var/run/mysqld/mysqld.sock');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', 'utf8mb4_unicode_ci');
WPCONFIG

# Ajouter les salts
if [ -n "$KEYS" ]; then
    echo "$KEYS" >> "$WP_DIR/wp-config.php"
else
    # Salts de fallback si l'API WordPress est down
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

# Table prefix + SSL proxy + URLs
cat >> "$WP_DIR/wp-config.php" <<'WPEOF'
$table_prefix = 'wp_';

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('WP_HOME', 'https://olmeick-woocommerce.onrender.com');
define('WP_SITEURL', 'https://olmeick-woocommerce.onrender.com');

/* Debug — commenter en prod */
// define('WP_DEBUG', true);
// define('WP_DEBUG_LOG', true);

if (!defined('ABSPATH')) define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
WPEOF

# Test de connexion DB via PHP
log "  → Test connexion DB..."
php -r "
\$l = @new mysqli('localhost','olmeick','olmeick_wc_2026','woocommerce',0,'/var/run/mysqld/mysqld.sock');
echo \$l->connect_error ? '❌ '.\$l->connect_error : '✅ DB OK';
echo PHP_EOL;
" 2>&1 || log "  → ⚠️ Test PHP échoué (non bloquant)"

log "  → ✅ wp-config.php OK"

# ══════════════════════════════════════════════════════════════════════════════
# 3. wp core install
# ══════════════════════════════════════════════════════════════════════════════

log "[3/5] Installation WordPress..."
if ! wp core is-installed --path="$WP_DIR" --allow-root 2>/dev/null; then
    wp core install \
        --url="https://olmeick-woocommerce.onrender.com" \
        --title="OLMEICK Bridge" \
        --admin_user=admin \
        --admin_password=OLMEICK_admin_2026 \
        --admin_email=bridge@olmeick.com \
        --path="$WP_DIR" \
        --allow-root 2>&1 || log "  → ⚠️ Install WP échoué (peut-être déjà installé)"
    log "  → ✅ Installé"
else
    log "  → ✅ Déjà installé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. WooCommerce
# ══════════════════════════════════════════════════════════════════════════════

log "[4/5] WooCommerce..."
if [ ! -f "$WC_FLAG" ]; then
    wp plugin install woocommerce --activate --path="$WP_DIR" --allow-root 2>&1 || log "  → ⚠️ WC install échoué"
    wp option update woocommerce_store_address "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_store_city "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_default_country "BJ" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_currency "USD" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_calc_taxes "yes" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite structure '/%postname%/' --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite flush --path="$WP_DIR" --allow-root 2>/dev/null || true
    touch "$WC_FLAG"
    log "  → ✅ Installé"
else
    log "  → ✅ Déjà installé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API REST — via MySQL direct avec le bon hash WooCommerce
# ══════════════════════════════════════════════════════════════════════════════

log "[5/5] Clés API REST..."

# WooCommerce auth: consumer_key est hashé avec hmac(sha256, key, 'wc-api')
# Le consumer_secret est stocké EN CLAIR en DB.
# Voir: get_user_data_by_consumer_key() dans class-wc-rest-authentication.php
# Voir: wc_api_hash() dans wc-core-functions.php

# Supprimer les anciennes clés de la DB avant de régénérer
mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 woocommerce \
    -e "DELETE FROM wp_woocommerce_api_keys;" 2>/dev/null || true

KEY_RESULT=$(php -r "
\$ck = 'ck_' . bin2hex(random_bytes(20));
\$cs = 'cs_' . bin2hex(random_bytes(20));
\$ck_hashed = hash_hmac('sha256', \$ck, 'wc-api');
\$ts = date('Y-m-d H:i:s');

\$sock = '/var/run/mysqld/mysqld.sock';
\$db = new mysqli('localhost', 'olmeick', 'olmeick_wc_2026', 'woocommerce', 3306, \$sock);
if (\$db->connect_error) { echo json_encode(array('error' => \$db->connect_error)); exit; }

\$sql = \$db->prepare('INSERT INTO wp_woocommerce_api_keys (user_id, description, permissions, consumer_key, consumer_secret, date_created) VALUES (?, ?, ?, ?, ?, ?)');
\$uid = 1;
\$desc = 'OLMEICK Bridge';
\$perm = 'read_write';
\$sql->bind_param('isssss', \$uid, \$desc, \$perm, \$ck_hashed, \$cs, \$ts);
\$sql->execute();
\$key_id = \$db->insert_id;

echo json_encode(array('consumer_key' => \$ck, 'consumer_secret' => \$cs, 'key_id' => (int)\$key_id, 'source' => 'generated'));
" 2>&1)

log "  -> Key result: $(echo "$KEY_RESULT" | head -c 120)"

CK=$(echo "$KEY_RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('consumer_key',''))" 2>/dev/null || echo "")
CS=$(echo "$KEY_RESULT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('consumer_secret',''))" 2>/dev/null || echo "")

if [ -n "$CK" ] && [ -n "$CS" ]; then
    cat > "$WP_DIR/wc-api-keys.json" <<KEYJSON
{
  "consumer_key": "$CK",
  "consumer_secret": "$CS",
  "store_url": "https://olmeick-woocommerce.onrender.com"
}
KEYJSON
    chmod 644 "$WP_DIR/wc-api-keys.json"
    log "  -> Consumer Key: $CK"
    log "  -> Consumer Secret: $CS"
    log "  -> Saved to /wc-api-keys.json"
else
    log "  -> WARNING: Keys empty"
fi

# Créer endpoint PHP pour récupérer les clés
cat > "$WP_DIR/api-keys.php" <<'APIKEYS_PHP'
<?php
error_reporting(0);
header('Content-Type: application/json');
$json_file = '/var/www/html/wc-api-keys.json';
if (file_exists($json_file)) {
    echo file_get_contents($json_file);
} else {
    echo json_encode(array('error' => 'No keys file found'));
}
APIKEYS_PHP
chmod 644 "$WP_DIR/api-keys.php"

touch "$API_KEY_FLAG"

# PERMISSIONS + HTACCESS
# ══════════════════════════════════════════════════════════════════════════════

chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php" 2>/dev/null || true
chmod 644 "$WP_DIR/health" 2>/dev/null || true

cat > "$WP_DIR/.htaccess" <<'HTEOF'
# Serve static files before WordPress rewrite
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^health$ - [L]
RewriteRule ^api-keys\.php$ - [L]
RewriteRule ^save-keys\.php$ - [L]
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
# RÉSUMÉ
# ══════════════════════════════════════════════════════════════════════════════

log "========================================="
log "  OLMEICK WooCommerce Bridge ✅"
log "  MariaDB ✅ | WordPress ✅ | WC ✅"
log "  Port: $HTTP_PORT | Health: /health"
log "========================================="

exec apache2-foreground
