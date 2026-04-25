# =============================================================================
# Image GLPI personnalisée avec support MariaDB/MySQL
#
# Pourquoi cette image custom plutôt que diouxx/glpi ?
#   1. diouxx/glpi télécharge GLPI au démarrage (internet requis chaque fois)
#   2. Cette image embarque GLPI 10.0.16 directement → démarrage sans internet
#   3. Contrôle total sur les extensions PHP et la configuration Apache
#
# Pourquoi MariaDB et non PostgreSQL ?
#   GLPI 10.x utilise exclusivement l'extension PHP `mysqli` pour ses connexions
#   (CLI glpi:database:install et installeur web). `mysqli` parle le protocole
#   MySQL → compatible MariaDB, incompatible PostgreSQL.
#   PostgreSQL reste dans la stack Docker pour l'exigence du TP (datasource Grafana).
#
# Base : PHP 8.2 + Apache 2.4 (Debian Bookworm)
# GLPI : 10.0.16 (LTS stable)
# =============================================================================

FROM php:8.2-apache

ARG GLPI_VERSION=10.0.16

# ---------------------------------------------------------------------------
# Dépendances système pour les extensions PHP
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    # Pour pdo_pgsql/pgsql (extensions PostgreSQL disponibles pour démo TP)
    libpq-dev \
    # Pour vérifier la connectivité MariaDB avant l'installation
    netcat-openbsd \
    # Pour télécharger l'archive GLPI
    curl \
    # Pour décompresser l'archive GLPI
    unzip \
    # Client MySQL/MariaDB — requis par entrypoint.sh pour charger seed_tickets.sql
    default-mysql-client \
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
        # Driver MySQL/MariaDB — utilisé par GLPI pour toutes ses connexions DB
        mysqli \
        # Driver PDO MySQL — requis par certains plugins GLPI
        pdo_mysql \
        # Extensions PostgreSQL (disponibles, non utilisées par GLPI lui-même)
        # Utile pour la démo TP et les scripts d'administration optionnels
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
# Téléchargement et installation de GLPI 10.0.16
# --strip-components=1 retire le préfixe "glpi/" de l'archive
# ---------------------------------------------------------------------------
RUN curl -fsSL \
    "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
    -o /tmp/glpi.tgz \
    && tar -xzf /tmp/glpi.tgz --strip-components=1 -C /var/www/html/ \
    && rm /tmp/glpi.tgz \
    && chown -R www-data:www-data /var/www/html/ \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \;

# ---------------------------------------------------------------------------
# Configuration Apache
# DocumentRoot = /var/www/html/public (recommandation de sécurité GLPI 10.x)
#   - Seul le répertoire public/ est accessible depuis le web
#   - config/, files/, install/ sont hors de portée du navigateur
#   - L'installation se fait via CLI (entrypoint.sh), pas via install.php
#     → pas besoin que install/ soit accessible par Apache
# ---------------------------------------------------------------------------
RUN echo '<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/public\n\
    \n\
    <Directory /var/www/html/public>\n\
        Options FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
        # Rediriger toutes les requêtes sans fichier réel vers index.php\n\
        # GLPI 10.x gère tout le routing via public/index.php\n\
        RewriteEngine On\n\
        RewriteCond %{REQUEST_FILENAME} !-f\n\
        RewriteRule ^ index.php [QSA,L]\n\
    </Directory>\n\
    \n\
    ErrorLog ${APACHE_LOG_DIR}/glpi_error.log\n\
    CustomLog ${APACHE_LOG_DIR}/glpi_access.log combined\n\
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

# ---------------------------------------------------------------------------
# Script d'entrée : installe la base automatiquement au 1er démarrage
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
COPY seed_tickets.sql /seed_tickets.sql
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
