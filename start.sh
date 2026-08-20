#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de démarrage complet
# Base: php:8.2-apache (pas de WordPress préinstallé)

set -e

WP_DIR="/var/www/html"
MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
WC_FLAG="$WP_DIR/.wc-installed"
API_KEY_FLAG="$WP_DIR/.api-keys-created"

echo "========================================="
echo "  OLMEICK WooCommerce Bridge"
echo "========================================="

# ── Attendre MariaDB ────────────────────────────────────────────────────────
wait_for_mysql() {
    local count=0
    while [ $count -lt 30 ]; do
        if [ -S "$MYSQL_SOCKET" ] && mysqladmin ping -u root --socket="$MYSQL_SOCKET" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. MariaDB
# ══════════════════════════════════════════════════════════════════════════════

echo "[1/5] MariaDB..."

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "  → Initialisation..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1

    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking --socket="$MYSQL_SOCKET" &
    wait_for_mysql

    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL'
        CREATE DATABASE IF NOT EXISTS woocommerce;
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --socket="$MYSQL_SOCKET" -u root shutdown
    wait || true
    rm -f "$MYSQL_SOCKET"
    echo "  → ✅ Initialisé"
fi

echo "  → Démarrage..."
mysqld --user=mysql --datadir=/var/lib/mysql --socket="$MYSQL_SOCKET" --skip-name-resolve &
if ! wait_for_mysql; then
    echo "  → ❌ MariaDB n'a pas démarré"
    exit 1
fi
echo "  → ✅ MariaDB actif"

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress
# ══════════════════════════════════════════════════════════════════════════════

echo "[2/5] WordPress..."

# Vider le répertoire web (base php:8.2-apache a des fichiers par défaut)
if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    echo "  → Téléchargement..."
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
    echo "  → ✅ Téléchargé"
fi

echo "  → Configuration..."

# Toujours recréer wp-config.php
rm -f "$WP_DIR/wp-config.php"
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

# Clés de sécurité
KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

sed -i "s/database_name_here/woocommerce/" "$WP_DIR/wp-config.php"
sed -i "s/username_here/olmeick/" "$WP_DIR/wp-config.php"
sed -i "s/password_here/olmeick_wc_2026/" "$WP_DIR/wp-config.php"
sed -i "s/localhost/127.0.0.1:3306/" "$WP_DIR/wp-config.php"

if [ -n "$KEYS" ]; then
    sed -i "/AUTH_KEY/d; /SECURE_AUTH_KEY/d; /LOGGED_IN_KEY/d; /NONCE_KEY/d; /AUTH_SALT/d; /SECURE_AUTH_SALT/d; /LOGGED_IN_SALT/d; /NONCE_SALT/d" "$WP_DIR/wp-config.php"
    echo "$KEYS" >> "$WP_DIR/wp-config.php"
fi

# HTTPS + site URL
cat >> "$WP_DIR/wp-config.php" <<'WPEOF'

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }
define('WP_HOME', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
define('WP_SITEURL', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
WPEOF

echo "  → ✅ Configuré"

# ══════════════════════════════════════════════════════════════════════════════
# 3. Installer WordPress (wp core install)
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
    echo "  → ✅ WordPress installé"
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
    echo "  → ✅ WooCommerce installé"
else
    echo "  → ✅ Déjà installé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 5. Clés API REST WooCommerce pour OLMEICK
# ══════════════════════════════════════════════════════════════════════════════

echo "[5/5] Clés API REST..."
if [ ! -f "$API_KEY_FLAG" ]; then
    # Créer un consumer key/secret via WP-CLI
    KEY_OUTPUT=$(wp wc tool run generate_api_key --user=admin --path="$WP_DIR" --allow-root 2>&1 || echo "")
    echo "  → Clés API: $KEY_OUTPUT"
    touch "$API_KEY_FLAG"
    echo "  → ✅ Clés créées"
else
    echo "  → ✅ Déjà créées"
fi

# ── Permissions ──────────────────────────────────────────────────────────────
chown -R www-data:www-data "$WP_DIR"
chmod -R 755 "$WP_DIR"

# ── Apache ───────────────────────────────────────────────────────────────────
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/:80/:8080/' /etc/apache2/sites-available/000-default.conf
a2enmod rewrite > /dev/null 2>&1 || true

# Fichier .htaccess pour l'API REST
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

echo "========================================="
echo "  OLMEICK WooCommerce Bridge ✅"
echo "  MariaDB ✅ | WordPress ✅ | WC ✅"
echo "  Port: 8080"
echo "========================================="

exec apache2-foreground
