# =============================================================================
# Image GLPI personnalisée avec support PostgreSQL
#
# Pourquoi cette image custom ?
# L'image diouxx/glpi (et la plupart des images GLPI publiques) est construite
# pour MySQL/MariaDB uniquement. GLPI 10.x supporte officiellement PostgreSQL 12+
# mais aucune image Docker officielle ne le préconfigure pour pgsql.
# Cette image installe les extensions PHP nécessaires (pdo_pgsql, pgsql) et
# lance l'installeur CLI de GLPI au premier démarrage via entrypoint.sh.
#
# Base : PHP 8.2 + Apache 2.4 (Debian Bookworm)
# GLPI : 10.0.16 (LTS stable, support PostgreSQL confirmé)
# =============================================================================

FROM php:8.2-apache

ARG GLPI_VERSION=10.0.16

# ---------------------------------------------------------------------------
# Dépendances système et bibliothèques C pour les extensions PHP
# Chaque lib correspond à une extension PHP installée ensuite.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Pour pdo_pgsql et pgsql
    libpq-dev \
    # Pour gd (images : JPEG, PNG, FreeType pour les graphes GLPI)
    libjpeg62-turbo-dev \
    libpng-dev \
    libfreetype6-dev \
    # Pour intl (internationalisation, GLPI fr_FR)
    libicu-dev \
    # Pour zip (installation de plugins GLPI)
    libzip-dev \
    # Pour ldap (authentification Active Directory optionnelle)
    libldap2-dev \
    # Pour bz2 (compression des sauvegardes GLPI)
    libbz2-dev \
    # Pour vérifier la connectivité PostgreSQL avant l'installation
    netcat-openbsd \
    # Pour télécharger l'archive GLPI
    curl \
    # Pour décompresser l'archive GLPI
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Extensions PHP requises par GLPI 10.x
# Source : https://glpi-install.readthedocs.io/en/latest/prerequisites.html
# ---------------------------------------------------------------------------
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    && docker-php-ext-configure ldap \
        --with-libdir=lib/x86_64-linux-gnu/ \
    && docker-php-ext-install -j$(nproc) \
        # Support PostgreSQL (PDO + extension native)
        pdo_pgsql \
        pgsql \
        # Traitement d'images (graphes, pièces jointes)
        gd \
        # Internationalisation (format dates, nombres)
        intl \
        # Gestion des archives (plugins)
        zip \
        # Performance PHP (cache opcode)
        opcache \
        # Authentification LDAP/AD (optionnel)
        ldap \
        # Compression des sauvegardes
        bz2 \
        # Métadonnées EXIF des images
        exif

# ---------------------------------------------------------------------------
# Configuration PHP optimisée pour GLPI
# ---------------------------------------------------------------------------
RUN { \
    echo 'memory_limit = 256M'; \
    echo 'max_execution_time = 300'; \
    echo 'upload_max_filesize = 20M'; \
    echo 'post_max_size = 20M'; \
    echo 'session.cookie_httponly = On'; \
    echo 'date.timezone = Europe/Paris'; \
} > /usr/local/etc/php/conf.d/glpi.ini

# ---------------------------------------------------------------------------
# Activation du module Apache mod_rewrite (requis par GLPI pour les URLs)
# ---------------------------------------------------------------------------
RUN a2enmod rewrite

# ---------------------------------------------------------------------------
# Téléchargement et installation de GLPI
# --strip-components=1 retire le préfixe "glpi/" de l'archive pour installer
# directement dans /var/www/html (évite /var/www/html/glpi/glpi/).
# ---------------------------------------------------------------------------
RUN curl -fsSL \
    "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
    -o /tmp/glpi.tgz \
    && tar -xzf /tmp/glpi.tgz --strip-components=1 -C /var/www/html/ \
    && rm /tmp/glpi.tgz \
    # Propriétaire www-data pour que Apache puisse écrire (config, fichiers)
    && chown -R www-data:www-data /var/www/html/ \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \;

# ---------------------------------------------------------------------------
# Configuration Apache : document root = public/ (bonne pratique GLPI 10.x)
# Le répertoire public/ est le seul point d'entrée web ; config/ et files/
# restent inaccessibles depuis le navigateur (sécurité).
# ---------------------------------------------------------------------------
RUN echo '<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/public\n\
    \n\
    <Directory /var/www/html/public>\n\
        Options FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
    \n\
    # Empêcher laccès direct aux répertoires sensibles\n\
    <Directory /var/www/html/config>\n\
        Require all denied\n\
    </Directory>\n\
    <Directory /var/www/html/files>\n\
        Require all denied\n\
    </Directory>\n\
    \n\
    ErrorLog ${APACHE_LOG_DIR}/glpi_error.log\n\
    CustomLog ${APACHE_LOG_DIR}/glpi_access.log combined\n\
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

# ---------------------------------------------------------------------------
# Script d'entrée : configure la base au premier démarrage
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
