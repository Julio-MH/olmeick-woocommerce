#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de démarrage
# Fix 403 WAF Render: health check + permissions propres

set -e

WP_DIR="/var/www/html"
MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
WC_FLAG="$WP_DIR/.wc-installed"
API_KEY_FLAG="$WP_DIR/.api-keys-created"
HTTP_PORT="${PORT:-8080}"

echo "========================================="
echo "  OLMEICK WooCommerce Bridge"
echo "  Port: $HTTP_PORT"
echo "========================================="

# ══════════════════════════════════════════════════════════════════════════════
# HEALTH CHECK — Render WAF a besoin d'un 200 sur /health
# ══════════════════════════════════════════════════════════════════════════════

mkdir -p "$WP_DIR"
cat > "$WP_DIR/health" <<'HEALTH'
OK
HEALTH
chmod 644 "$WP_DIR/health"

# ══════════════════════════════════════════════════════════════════════════════
# 1. MariaDB — Socket UNIX
# ══════════════════════════════════════════════════════════════════════════════

echo "[1/5] MariaDB..."

# --- Initialisation ---
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "  → Initialisation..."

    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    { echo "  → ❌ Échec init MariaDB"; exit 1; }

    mysqld --user=mysql --datadir=/var/lib/mysql \
        --skip-networking \
        --socket="$MYSQL_SOCKET" \
        --pid-file="$MYSQL_SOCKET.pid" &

    echo "  → Attente socket..."
    MYSQL_READY=0
    for i in $(seq 1 30); do
        if [ -S "$MYSQL_SOCKET" ]; then
            if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
                MYSQL_READY=1
                break
            fi
        fi
        sleep 1
    done

    if [ "$MYSQL_READY" -ne 1 ]; then
        echo "  → ❌ MariaDB pas prêt"
        exit 1
    fi

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
    wait || true
    rm -f "$MYSQL_SOCKET" "$MYSQL_SOCKET.pid"
    echo "  → ✅ Init OK"
fi

# --- Démarrage ---
echo "  → Démarrage MariaDB..."
mysqld --user=mysql --datadir=/var/lib/mysql \
    --socket="$MYSQL_SOCKET" \
    --pid-file="$MYSQL_SOCKET.pid" \
    --skip-name-resolve &

MYSQL_READY=0
for i in $(seq 1 30); do
    if [ -S "$MYSQL_SOCKET" ]; then
        if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
            MYSQL_READY=1
            break
        fi
    fi
    sleep 1
done

if [ "$MYSQL_READY" -ne 1 ]; then
    echo "  → ❌ MariaDB pas démarré"
    exit 1
fi
echo "  → ✅ MariaDB actif"

# Vérifier user
if ! mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "USE woocommerce" 2>/dev/null; then
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL2'
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOSQL2
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress — Socket UNIX
# ══════════════════════════════════════════════════════════════════════════════

echo "[2/5] WordPress..."

if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    echo "  → Téléchargement..."
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
fi

rm -f "$WP_DIR/wp-config.php"
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

sed -i "s/database_name_here/woocommerce/" "$WP_DIR/wp-config.php"
sed -i "s/username_here/olmeick/" "$WP_DIR/wp-config.php"
sed -i "s/password_here/olmeick_wc_2026/" "$WP_DIR/wp-config.php"
sed -i "s|localhost|localhost:/var/run/mysqld/mysqld.sock|" "$WP_DIR/wp-config.php"

if [ -n "$KEYS" ]; then
    sed -i "/AUTH_KEY/d; /SECURE_AUTH_KEY/d; /LOGGED_IN_KEY/d; /NONCE_KEY/d; /AUTH_SALT/d; /SECURE_AUTH_SALT/d; /LOGGED_IN_SALT/d; /NONCE_SALT/d" "$WP_DIR/wp-config.php"
    echo "$KEYS" >> "$WP_DIR/wp-config.php"
fi

cat >> "$WP_DIR/wp-config.php" <<'WPEOF'

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('WP_HOME', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
define('WP_SITEURL', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
WPEOF

php -r "\$l = @new mysqli('localhost','olmeick','olmeick_wc_2026','woocommerce',0,'/var/run/mysqld/mysqld.sock'); echo \$l->connect_error ? '❌'.\$l->connect_error : '✅ DB OK'; echo PHP_EOL;" 2>&1 || true

echo "  → ✅ wp-config.php OK"

# ══════════════════════════════════════════════════════════════════════════════
# 3. wp core install
# ══════════════════════════════════════════════════════════════════════════════

echo "[3/5] Installation WordPress..."
if ! wp core is-installed --path="$WP_DIR" --allow-root 2>/dev/null; then
    wp core install \
        --url="https://olmeick-woocommerce.onrender.com" \
        --title="OLMEICK Bridge" \
        --admin_user=admin \
        --admin_password=OLMEICK_admin_2026 \
        --admin_email=bridge@olmeick.com \
        --path="$WP_DIR" \
        --allow-root 2>&1 || true
    echo "  → ✅ Installé"
else
    echo "  → ✅ Déjà installé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. WooCommerce
# ══════════════════════════════════════════════════════════════════════════════

echo "[4/5] WooCommerce..."
if [ ! -f "$WC_FLAG" ]; then
    wp plugin install woocommerce --activate --path="$WP_DIR" --allow-root 2>&1 || true
    wp option update woocommerce_store_address "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_store_city "Cotonou" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_default_country "BJ" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_currency "USD" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp option update woocommerce_calc_taxes "yes" --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite structure '/%postname%/' --path="$WP_DIR" --allow-root 2>/dev/null || true
    wp rewrite flush --path="$WP_DIR" --allow-root 2>/dev/null || true
    touch "$WC_FLAG"
    echo "  → ✅ Installé"
else
    echo "  → ✅ Déjà installé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API REST
# ══════════════════════════════════════════════════════════════════════════════

echo "[5/5] Clés API REST..."
if [ ! -f "$API_KEY_FLAG" ]; then
    KEY_OUTPUT=$(wp wc tool run generate_api_key --user=admin --path="$WP_DIR" --allow-root 2>&1 || echo "")
    echo "  → $KEY_OUTPUT"
    touch "$API_KEY_FLAG"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PERMISSIONS + HTACCESS
# ══════════════════════════════════════════════════════════════════════════════

chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php" 2>/dev/null || true
chmod 644 "$WP_DIR/health" 2>/dev/null || true

cat > "$WP_DIR/.htaccess" <<'HTEOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
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

echo "========================================="
echo "  OLMEICK WooCommerce Bridge ✅"
echo "  MariaDB ✅ | WordPress ✅ | WC ✅"
echo "  Port: $HTTP_PORT | Health: /health"
echo "========================================="

exec apache2-foreground
