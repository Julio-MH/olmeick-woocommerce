#!/bin/bash
# OLMEICK WooCommerce Bridge — Script de démarrage
# Lance MySQL, WordPress et installe WooCommerce automatiquement

set -e

WP_DIR="/var/www/html"
WC_INSTALLED_FLAG="$WP_DIR/.wc-installed"

echo "========================================="
echo "  OLMEICK WooCommerce Bridge"
echo "  Démarrage du serveur..."
echo "========================================="

# ── 1. Initialiser MySQL si premier lancement ────────────────────────────────
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[1/4] Initialisation de MySQL..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking &
    sleep 3
    mysql -u root <<-EOSQL
        CREATE DATABASE IF NOT EXISTS woocommerce;
        CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
        GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
        FLUSH PRIVILEGES;
EOSQL
    mysqladmin -u root shutdown
    echo "[1/4] MySQL initialisé."
else
    echo "[1/4] MySQL déjà initialisé."
fi

# ── 2. Démarrer MySQL ────────────────────────────────────────────────────────
echo "[2/4] Démarrage de MySQL..."
mysqld --user=mysql --datadir=/var/lib/mysql &
MYSQL_PID=$!
sleep 3

# Vérifier que MySQL tourne
if ! kill -0 $MYSQL_PID 2>/dev/null; then
    echo "ERREUR: MySQL n'a pas démarré."
    exit 1
fi
echo "[2/4] MySQL actif (PID: $MYSQL_PID)."

# ── 3. Installer WordPress si nécessaire ──────────────────────────────────────
if [ ! -f "$WP_DIR/wp-includes/version.php" ]; then
    echo "[3/4] Téléchargement de WordPress..."
    rm -rf $WP_DIR/*
    wp core download --path=$WP_DIR --allow-root 2>/dev/null || \
        curl -sL https://wordpress.org/latest.tar.gz | tar xz --strip-components=1 -C $WP_DIR
fi
echo "[3/4] WordPress prêt."

# ── 4. Configurer WordPress ───────────────────────────────────────────────────
if [ ! -f "$WP_DIR/wp-config.php" ]; then
    echo "[3.5/4] Configuration de WordPress..."
    cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php

    # Générer les clés de sécurité
    KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

    sed -i "s/database_name_here/woocommerce/" $WP_DIR/wp-config.php
    sed -i "s/username_here/olmeick/" $WP_DIR/wp-config.php
    sed -i "s/password_here/olmeick_wc_2026/" $WP_DIR/wp-config.php
    sed -i "s/localhost/127.0.0.1:3306/" $WP_DIR/wp-config.php

    if [ -n "$KEYS" ]; then
        # Remplacer les placeholders de clés
        sed -i "/AUTH_KEY/d; /SECURE_AUTH_KEY/d; /LOGGED_IN_KEY/d; /NONCE_KEY/d; /AUTH_SALT/d; /SECURE_AUTH_SALT/d; /LOGGED_IN_SALT/d; /NONCE_SALT/d" $WP_DIR/wp-config.php
        echo "$KEYS" >> $WP_DIR/wp-config.php
    fi

    # Forcer le HTTPS derrière le reverse proxy Render
    echo "if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { \$_SERVER['HTTPS'] = 'on'; }" >> $WP_DIR/wp-config.php
    echo "define('WP_HOME', getenv('OLMEICK_SITE_URL') ?: 'https://olmeick.vercel.app');" >> $WP_DIR/wp-config.php

    echo "[3.5/4] WordPress configuré."
fi

# ── 5. Installer WooCommerce si pas encore fait ───────────────────────────────
if [ ! -f "$WC_INSTALLED_FLAG" ]; then
    echo "[4/4] Installation de WooCommerce..."

    # Installer WP-CLI si absent
    if [ ! -f /usr/local/bin/wp ]; then
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi

    # Installer et activer WooCommerce
    wp plugin install woocommerce --activate --path=$WP_DIR --allow-root 2>/dev/null || true

    # Activer l'API REST (par défaut activée)
    wp option update woocommerce_store_address "Cotonou" --path=$WP_DIR --allow-root 2>/dev/null || true
    wp option update woocommerce_store_city "Cotonou" --path=$WP_DIR --allow-root 2>/dev/null || true
    wp option update woocommerce_default_country "BJ" --path=$WP_DIR --allow-root 2>/dev/null || true
    wp option update woocommerce_currency "USD" --path=$WP_DIR --allow-root 2>/dev/null || true
    wp option update woocommerce_calc_taxes "yes" --path=$WP_DIR --allow-root 2>/dev/null || true

    # Créer les clés API REST pour OLMEICK
    echo "[4/4] Création des clés API REST..."
    wp wc --list --path=$WP_DIR --allow-root 2>/dev/null || true

    touch $WC_INSTALLED_FLAG
    echo "[4/4] WooCommerce installé et configuré."
else
    echo "[4/4] WooCommerce déjà installé."
fi

# ── 6. Fixer les permissions ──────────────────────────────────────────────────
chown -R www-data:www-data $WP_DIR
chmod -R 755 $WP_DIR

# ── 7. Configurer Apache ─────────────────────────────────────────────────────
# Écouter sur le port 8080 (Render exige 8080)
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/:80/:8080/' /etc/apache2/sites-available/000-default.conf

# Activer les modules Apache nécessaires
a2enmod rewrite > /dev/null 2>&1 || true
a2enmod proxy > /dev/null 2>&1 || true
a2enmod proxy_http > /dev/null 2>&1 || true

echo "========================================="
echo "  OLMEICK WooCommerce Bridge"
echo "  Serveur prêt sur le port 8080"
echo "========================================="

# ── 8. Démarrer Apache ───────────────────────────────────────────────────────
exec apache2-foreground
