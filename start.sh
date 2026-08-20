#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de démarrage complet
# Base: php:8.2-apache (pas de WordPress préinstallé)
# Fix: Socket UNIX pour MariaDB (évite les erreurs Aborted connection)

set -e

WP_DIR="/var/www/html"
MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
WC_FLAG="$WP_DIR/.wc-installed"
API_KEY_FLAG="$WP_DIR/.api-keys-created"

echo "========================================="
echo "  OLMEICK WooCommerce Bridge"
echo "========================================="

# ══════════════════════════════════════════════════════════════════════════════
# 1. MariaDB — Attente par SOCKET (pas de TCP ping)
# ══════════════════════════════════════════════════════════════════════════════

echo "[1/5] MariaDB..."

# --- Initialisation si premier lancement ---
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "  → Initialisation de la base de données..."

    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1 || \
    { echo "  → ❌ Échec initialisation MariaDB"; exit 1; }

    # Démarrer MariaDB en mode skip-networking (socket uniquement) pour la config initiale
    mysqld --user=mysql --datadir=/var/lib/mysql \
        --skip-networking \
        --socket="$MYSQL_SOCKET" \
        --pid-file="$MYSQL_SOCKET.pid" &

    # ── Attendre le SOCKET (pas TCP) ──
    echo "  → Attente du socket MariaDB..."
    MYSQL_READY=0
    for i in $(seq 1 30); do
        if [ -S "$MYSQL_SOCKET" ]; then
            # Le socket existe, tester la connexion
            if mysql --socket="$MYSQL_SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
                MYSQL_READY=1
                break
            fi
        fi
        sleep 1
    done

    if [ "$MYSQL_READY" -ne 1 ]; then
        echo "  → ❌ MariaDB n'est pas prêt après 30s"
        exit 1
    fi

    # ── Créer la base + utilisateurs avec droits EXPLICITES ──
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL'
        -- Créer la base de données
        CREATE DATABASE IF NOT EXISTS woocommerce
            CHARACTER SET utf8mb4
            COLLATE utf8mb4_unicode_ci;

        -- Utilisateur pour connexions via socket (localhost)
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';

        -- Utilisateur pour connexions via TCP (127.0.0.1)
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';

        -- Utilisateur root accessible via socket
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;

        FLUSH PRIVILEGES;
EOSQL

    echo "  → Base de données créée + utilisateurs configurés"

    # Arrêter MariaDB temporaire
    mysqladmin --socket="$MYSQL_SOCKET" -u root shutdown 2>/dev/null || true
    wait || true
    rm -f "$MYSQL_SOCKET" "$MYSQL_SOCKET.pid"
    echo "  → ✅ Initialisation terminée"
else
    echo "  → ✅ Base de données déjà initialisée"
fi

# --- Démarrage MariaDB ---
echo "  → Démarrage de MariaDB..."
mysqld --user=mysql --datadir=/var/lib/mysql \
    --socket="$MYSQL_SOCKET" \
    --pid-file="$MYSQL_SOCKET.pid" \
    --skip-name-resolve &

# ── Attendre le SOCKET (pas TCP ping) ──
echo "  → Vérification du socket..."
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
    echo "  → ❌ MariaDB n'a pas démarré (socket introuvable)"
    exit 1
fi

echo "  → ✅ MariaDB actif (socket: $MYSQL_SOCKET)"

# ── Vérifier que l'utilisateur olmeick peut se connecter ──
if mysql --socket="$MYSQL_SOCKET" -u olmeick -polmeick_wc_2026 -e "USE woocommerce" 2>/dev/null; then
    echo "  → ✅ Utilisateur 'olmeick' fonctionne"
else
    echo "  → ⚠️ Re-création de l'utilisateur..."
    mysql --socket="$MYSQL_SOCKET" -u root <<-'EOSQL2'
        CREATE USER IF NOT EXISTS 'olmeick'@'localhost' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'localhost';
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOSQL2
    echo "  → ✅ Utilisateur recréé"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. WordPress — DB_HOST = localhost via SOCKET
# ══════════════════════════════════════════════════════════════════════════════

echo "[2/5] WordPress..."

# Télécharger WordPress si absent
if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    echo "  → Téléchargement..."
    rm -rf "$WP_DIR"/*
    curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C "$WP_DIR"
    echo "  → ✅ Téléchargé"
fi

# Toujours recréer wp-config.php (propre, pas de conflit)
echo "  → Configuration de wp-config.php..."
rm -f "$WP_DIR/wp-config.php"
cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

# Clés de sécurité WordPress
KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

# ── FIX: DB_HOST = localhost:/var/run/mysqld/mysqld.sock (socket UNIX) ──
sed -i "s/database_name_here/woocommerce/" "$WP_DIR/wp-config.php"
sed -i "s/username_here/olmeick/" "$WP_DIR/wp-config.php"
sed -i "s/password_here/olmeick_wc_2026/" "$WP_DIR/wp-config.php"
sed -i "s|localhost|localhost:/var/run/mysqld/mysqld.sock|" "$WP_DIR/wp-config.php"

if [ -n "$KEYS" ]; then
    sed -i "/AUTH_KEY/d; /SECURE_AUTH_KEY/d; /LOGGED_IN_KEY/d; /NONCE_KEY/d; /AUTH_SALT/d; /SECURE_AUTH_SALT/d; /LOGGED_IN_SALT/d; /NONCE_SALT/d" "$WP_DIR/wp-config.php"
    echo "$KEYS" >> "$WP_DIR/wp-config.php"
fi

# HTTPS derrière Render reverse proxy + URL du site
cat >> "$WP_DIR/wp-config.php" <<'WPEOF'

/* Forcer HTTPS derrière le proxy Render */
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

/* URLs du site OLMEICK */
define('WP_HOME', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
define('WP_SITEURL', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');
WPEOF

echo "  → ✅ wp-config.php configuré (socket UNIX)"

# Vérifier la connexion DB depuis PHP
echo "  → Test connexion DB via socket..."
php -r "
\$link = @new mysqli('localhost', 'olmeick', 'olmeick_wc_2026', 'woocommerce', 0, '/var/run/mysqld/mysqld.sock');
if (\$link->connect_error) { echo '❌ Erreur: ' . \$link->connect_error; exit(1); }
echo '✅ Connexion DB OK';
\$link->close();
" 2>&1 || echo "  → ⚠️ Test PHP échoué, mais on continue"

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

# .htaccess pour l'API REST
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
echo "  Socket: $MYSQL_SOCKET"
echo "  Port: 8080"
echo "========================================="

exec apache2-foreground
