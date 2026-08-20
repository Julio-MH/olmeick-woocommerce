# OLMEICK WooCommerce Bridge — Docker Image
# WordPress + WooCommerce + MariaDB dans un seul conteneur
# Optimisé pour Render.com Free Tier (512MB RAM)

FROM wordpress:6.7-php8.2-apache

# Installer MariaDB (plus léger que MySQL sur 512MB)
RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Configuration MariaDB optimisée pour 512MB RAM
RUN printf '[mysqld]\ninnodb_buffer_pool_size = 32M\ninnodb_log_file_size = 8M\ninnodb_log_buffer_size = 4M\ninnodb_file_per_table = 1\nmax_allowed_packet = 8M\nkey_buffer_size = 16M\ntable_open_cache = 64\nsort_buffer_size = 256K\nread_buffer_size = 256K\nthread_cache_size = 4\ntmp_table_size = 16M\nmax_heap_table_size = 16M\nskip-name-resolve\nbind-address = 127.0.0.1\nport = 3306\n' > /etc/mysql/mariadb.conf.d/99-olmeick.cnf

# Créer le répertoire de socket MySQL
RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && chmod 755 /var/run/mysqld

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
