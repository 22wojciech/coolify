# ========================
# Stage 1: Composer + dependencies
# ========================
FROM composer:2 AS composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --optimize-autoloader

# ========================
# Stage 2: Node.js build (Vite + assets)
# ========================
FROM node:20-alpine AS frontend

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile

COPY . .
RUN npm run build

# ========================
# Stage 3: Final production image
# ========================
FROM php:8.3-fpm AS production

# Instalacja zależności systemowych
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    unzip \
    git \
    curl \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd pdo pdo_mysql zip bcmath opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Konfiguracja PHP
COPY .docker/php.ini /usr/local/etc/php/conf.d/app.ini

# Kopiowanie aplikacji
WORKDIR /var/www/html

# Kopiujemy kod źródłowy
COPY . .

# Kopiujemy vendor z composera i built assets
COPY --from=composer /app/vendor ./vendor
COPY --from=frontend /app/public/build ./public/build

# Uprawnienia
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage /var/www/html/bootstrap/cache

# Konfiguracja Nginx
COPY .docker/nginx.conf /etc/nginx/sites-available/default

# Supervisor (zarządza php-fpm + nginx)
COPY .docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
