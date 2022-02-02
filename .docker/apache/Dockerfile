FROM composer:latest as builder

RUN set -eux; \
    composer create-project roots/bedrock /app; \
    rm -f /app/.env

FROM php:8.0-apache

WORKDIR /var/www

# Persistent Dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y curl zip sendmail git; \
    apt-get install -y gettext-base; \
    rm -rf /var/lib/apt/lists/*

# Node Development Tools
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
ENV NVM_DIR=/root/.nvm
RUN . ${NVM_DIR}/nvm.sh && nvm install --lts
RUN . ${NVM_DIR}/nvm.sh && nvm use --lts
RUN . ${NVM_DIR}/nvm.sh && nvm alias default lts/*
ENV PATH="$NVM_BIN:$PATH"

# WP Command-line Interface
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
RUN chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
RUN wp --allow-root package install aaemnnosttv/wp-cli-dotenv-command:^2.0

# PHP Extensions
# Wordpress Requirements: https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
            libfreetype6-dev \
            libjpeg-dev \
            libmagickwand-dev \
            libpng-dev \
            libwebp-dev \
            libzip-dev \
            libmcrypt-dev \
    ; \
    docker-php-ext-configure gd \
            --with-freetype \
            --with-jpeg \
            --with-webp \
    ; \
    docker-php-ext-install \
            bcmath \
            exif \
            gd \
            mysqli \
            zip \
    ; \
    # https://pecl.php.net/package/imagick
    # https://pecl.php.net/package/mcrypt
    pecl install imagick mcrypt; \
    docker-php-ext-enable imagick mcrypt; \
    rm -r /tmp/pear; \
    \
    # Reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
            | awk '/=>/ { print $3 }' \
            | sort -u \
            | xargs -r dpkg-query -S \
            | cut -d: -f1 \
            | sort -u \
            | xargs -rt apt-mark manual \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# Set Recommended PHP.ini Settings
# See https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Configure Error Logging
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
# https://www.php.net/manual/en/errorfunc.constants.php
RUN { \
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

RUN set -eux; \
	a2enmod rewrite expires; \
    # https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
	a2enmod remoteip; \
	{ \
		echo 'RemoteIPHeader X-Forwarded-For'; \
        # These IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
		echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
		echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
		echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
		echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
	} > /etc/apache2/conf-available/remoteip.conf; \
	a2enconf remoteip; \
    # Replace all instances of "%h" with "%a" in LogFormat
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

COPY --from=builder /usr/bin/composer /usr/bin/composer
COPY --from=builder --chown=www-data:www-data /app /usr/src/bedrock

RUN set -eux; \
    # https://wordpress.org/support/article/htaccess/
    [ ! -e /usr/src/bedrock/web/.htaccess ]; \
    { \
		echo '# BEGIN WordPress'; \
		echo ''; \
		echo 'RewriteEngine On'; \
		echo 'RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]'; \
		echo 'RewriteBase /'; \
		echo 'RewriteRule ^index\.php$ - [L]'; \
		echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
		echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
		echo 'RewriteRule . /index.php [L]'; \
		echo ''; \
		echo '# END WordPress'; \
	} > /usr/src/bedrock/web/.htaccess; \
	chown -R www-data:www-data /usr/src/bedrock; \
    # Pre-create app (and single-level children) for folks who want to bind-mount themes, etc so permissions are pre-created properly instead of root:root
    mkdir web; \
    mkdir web/app; \
	for dir in /usr/src/bedrock/web/app/*/ cache; do \
		dir="$(basename "${dir%/}")"; \
		mkdir "web/app/$dir"; \
	done; \
    chown -R www-data:www-data web/app; \
	chmod -R 777 web/app

VOLUME /var/www

COPY --chown=www-data:www-data .env.template /usr/src/bedrock/
COPY --chown=www-data:www-data .env.example /usr/src/bedrock/
COPY --chown=www-data:www-data .wp-env.json /usr/src/bedrock/
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/

# Configure Sendmail
RUN echo "sendmail_path=/usr/sbin/sendmail -t -i" >> /usr/local/etc/php/conf.d/sendmail.ini
RUN sed -i '/#!\/bin\/sh/aservice sendmail restart' /usr/local/bin/docker-php-entrypoint
RUN sed -i '/#!\/bin\/sh/aecho "$(hostname -i)\t$(hostname) $(hostname).localhost" >> /etc/hosts' /usr/local/bin/docker-php-entrypoint

# Configure Apache
ENV APACHE_DOCUMENT_ROOT=/var/www/web
RUN set -eux; \
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf; \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf; \
    sed -i "s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf; \
    echo "ServerName local.muhit.me" >> /etc/apache2/apache2.conf; \
    a2enmod rewrite && a2enmod ssl; \
    a2dissite 000-default && a2ensite 000-default; \
    service apache2 restart

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]