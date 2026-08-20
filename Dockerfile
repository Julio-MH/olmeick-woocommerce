# OLMEICK WooCommerce Bridge — Docker Image
# WordPress + WooCommerce + MySQL dans un seul conteneur
# Optimisé pour Render.com Free Tier (512MB RAM)

FROM wordpress:6.7-php8.2-apache

# Installer MySQL
RUN apt-get update && apt-get install -y \
    default-mysql-server \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Pré-configurer MySQL
RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# Script d'initialisation MySQL
COPY init-mysql.sh /usr/local/bin/init-mysql.sh
RUN chmod +x /usr/local/bin/init-mysql.sh

# Script de démarrage (MySQL + WordPress + WooCommerce)
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Variables d'environnement pour WordPress
ENV WORDPRESS_DB_HOST=127.0.0.1:3306
ENV WORDPRESS_DB_USER=olmeick
ENV WORDPRESS_DB_PASSWORD=olmeick_wc_2026
ENV WORDPRESS_DB_NAME=woocommerce
ENV WORDPRESS_TABLE_PREFIX=wp_
ENV WORDPRESS_DEBUG=false

# Variables OLMEICK pour la sync
ENV OLMEICK_SITE_URL=https://olmeick.vercel.app
ENV OLMEICK_SUPABASE_URL=
ENV OLMEICK_SUPABASE_SERVICE_KEY=

# Exposer le port
EXPOSE 8080

# Démarrer
CMD ["/usr/local/bin/start.sh"]
