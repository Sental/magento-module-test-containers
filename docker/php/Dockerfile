ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-bookworm

# Build/runtime libraries for the extensions Mage-OS 3.4 requires.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip zip curl default-mysql-client \
        # procps supplies `ps`. The integration test framework measures memory
        # with `ps --pid N --format rss`, and on failure falls back to Windows'
        # tasklist.exe — which surfaces as a baffling "tasklist.exe: not found"
        # fatal that hides the real error. Keep the Linux path working.
        procps \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libicu-dev libxml2-dev libxslt1-dev libzip-dev libsodium-dev \
        libonig-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath gd intl mbstring pdo_mysql soap sockets sodium xsl zip opcache

# Composer 2 from the official image.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY php.ini /usr/local/etc/php/conf.d/zz-magento.ini

# Run as the host user so files written into the bind mount stay editable
# outside the container. Overridden per-invocation by the bin/ wrappers.
ARG UID=1000
ARG GID=1000
RUN groupmod -g "${GID}" www-data 2>/dev/null || true \
    && usermod -u "${UID}" -g "${GID}" www-data 2>/dev/null || true \
    && mkdir -p /composer && chown -R "${UID}:${GID}" /composer

WORKDIR /var/www/html
