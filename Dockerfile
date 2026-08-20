# OLMEICK WooCommerce Bridge — Docker Image
# Base légère php:8.2-apache, on installe tout nous-mêmes
# Pas de WordPress préinstallé = pas de entrypoint qui casse tout

FROM php:8.2-apache

# Installer MariaDB + dépendances PHP
RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    libzip-dev \
    unzip \
    curl \
    && docker-php-ext-install zip mysqli pdo pdo_mysql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configuration MariaDB optimisée pour 512MB RAM
# skip-name-resolve = pas de DNS lookup (plus rapide)
# bind-address = 127.0.0.1 pour TCP local
RUN printf '[mysqld]\n\
innodb_buffer_pool_size = 32M\n\
innodb_log_file_size = 8M\n\
innodb_log_buffer_size = 4M\n\
innodb_file_per_table = 1\n\
max_allowed_packet = 8M\n\
key_buffer_size = 16M\n\
table_open_cache = 64\n\
sort_buffer_size = 256K\n\
read_buffer_size = 256K\n\
thread_cache_size = 4\n\
tmp_table_size = 16M\n\
max_heap_table_size = 16M\n\
skip-name-resolve\n\
bind-address = 127.0.0.1\n\
port = 3306\n\
socket = /var/run/mysqld/mysqld.sock\n' > /etc/mysql/mariadb.conf.d/99-olmeick.cnf

# Répertoire socket + permissions
RUN mkdir -p /var/run/mysqld \
    && chown mysql:mysql /var/run/mysqld \
    && chmod 755 /var/run/mysqld

# Installer WP-CLI
RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

# Script de démarrage
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Port Render
EXPOSE 8080

# Variables
ENV OLMEICK_SITE_URL=https://olmeick.vercel.app

ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["apache2-foreground"]
