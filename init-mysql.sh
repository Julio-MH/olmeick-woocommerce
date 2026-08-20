#!/bin/bash
# Initialisation MySQL pour OLMEICK WooCommerce Bridge

set -e

echo "[OLMEICK] Initialisation de MySQL..."

# Démarrer MySQL temporairement pour configurer
mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking &
sleep 3

# Créer la base de données et l'utilisateur
mysql -u root <<-EOSQL
    CREATE DATABASE IF NOT EXISTS woocommerce;
    CREATE USER IF NOT EXISTS 'olmeick'@'127.0.0.1' IDENTIFIED BY 'olmeick_wc_2026';
    GRANT ALL PRIVILEGES ON woocommerce.* TO 'olmeick'@'127.0.0.1';
    FLUSH PRIVILEGES;
EOSQL

# Arrêter MySQL temporaire
mysqladmin -u root shutdown

echo "[OLMEICK] MySQL initialisé avec succès."
