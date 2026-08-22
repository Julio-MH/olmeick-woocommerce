# OLMEICK WooCommerce Bridge — Docker Image
FROM php:8.2-apache

RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    libzip-dev \
    unzip \
    curl \
    openssl \
    && docker-php-ext-install zip mysqli pdo pdo_mysql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN printf '[mysqld]\ninnodb_buffer_pool_size = 32M\ninnodb_log_file_size = 8M\nmax_allowed_packet = 8M\nkey_buffer_size = 16M\nskip-name-resolve\nbind-address = 127.0.0.1\nsocket = /var/run/mysqld/mysqld.sock\n' > /etc/mysql/mariadb.conf.d/99-olmeick.cnf

RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && chmod 755 /var/run/mysqld

RUN printf '<VirtualHost *:8080>\n    ServerName olmeick-woocommerce\n    DocumentRoot /var/www/html\n    <Directory /var/www/html>\n        Options -Indexes +FollowSymLinks +MultiViews\n        AllowOverride All\n        Require all granted\n    </Directory>\n    <Location "/health">\n        Require all granted\n    </Location>\n    ErrorLog ${APACHE_LOG_DIR}/error.log\n    CustomLog ${APACHE_LOG_DIR}/access.log combined\n</VirtualHost>\n' > /etc/apache2/sites-available/000-default.conf

RUN printf 'Listen 8080\n' > /etc/apache2/ports.conf
RUN a2enmod rewrite headers proxy proxy_http

RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 8080

ENV PORT=8080

ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["apache2-foreground"]
