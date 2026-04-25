#!/bin/bash
# =============================================================================
# Script d'entrée GLPI — Installation automatique via le CLI GLPI + MariaDB
#
# Pourquoi MariaDB et non PostgreSQL ?
# Le CLI GLPI (glpi:database:install) et l'installeur web (install/install.php)
# n'utilisent que l'extension PHP mysqli — incompatible avec PostgreSQL (port 5432).
# MariaDB parle le protocole MySQL, donc mysqli fonctionne parfaitement avec elle.
# PostgreSQL reste dans la stack Docker pour l'exigence du TP mais GLPI n'y
# est pas connecté.
#
# Ce script au premier démarrage :
#   1. Attend que MariaDB soit joignable (TCP)
#   2. Corrige les permissions des volumes Docker
#   3. Exécute glpi:database:install (CLI, non-interactif)
#   4. Démarre Apache
#
# Redémarrages suivants : config_db.php existe → passe directement à Apache.
# =============================================================================

set -e

MARIADB_HOST="${MARIADB_HOST:-mariadb}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
MARIADB_DATABASE="${MARIADB_DATABASE:-glpi}"
MARIADB_USER="${MARIADB_USER:-glpi_user}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-glpi}"

echo "============================================================"
echo " GLPI — Démarrage du conteneur"
echo " Base de données : ${MARIADB_HOST}:${MARIADB_PORT}/${MARIADB_DATABASE}"
echo "============================================================"

# ---------------------------------------------------------------------------
# [1/3] Attendre que MariaDB soit joignable (TCP)
# ---------------------------------------------------------------------------
echo "[1/3] Attente de MariaDB à ${MARIADB_HOST}:${MARIADB_PORT}..."
TIMEOUT=90
while ! nc -z "${MARIADB_HOST}" "${MARIADB_PORT}" 2>/dev/null; do
    TIMEOUT=$((TIMEOUT - 1))
    if [ "${TIMEOUT}" -le 0 ]; then
        echo "ERREUR : MariaDB non joignable après 90s. Vérifier le service mariadb."
        exit 1
    fi
    sleep 2
done
echo "  MariaDB est joignable."

# ---------------------------------------------------------------------------
# Corriger les permissions des répertoires inscriptibles
# Les volumes Docker sont montés root:root par défaut.
# Apache tourne en www-data et doit pouvoir écrire dans files/ et config/.
# ---------------------------------------------------------------------------
mkdir -p /var/www/html/files/_log \
         /var/www/html/files/_tmp \
         /var/www/html/files/_sessions \
         /var/www/html/marketplace
chown -R www-data:www-data \
    /var/www/html/files/ \
    /var/www/html/config/ \
    /var/www/html/plugins/ \
    /var/www/html/marketplace/ 2>/dev/null || true
chmod -R 755 /var/www/html/files/ /var/www/html/config/ 2>/dev/null || true

# ---------------------------------------------------------------------------
# [2/3] Installation de la base GLPI (premier démarrage uniquement)
# ---------------------------------------------------------------------------
CONFIG_DB="/var/www/html/config/config_db.php"

if [ -f "${CONFIG_DB}" ]; then
    echo "[2/3] GLPI déjà installé (config_db.php présent) — démarrage direct."
else
    echo "[2/3] Première installation — initialisation de la base GLPI..."
    echo "      Connexion : ${MARIADB_USER}@${MARIADB_HOST}:${MARIADB_PORT}/${MARIADB_DATABASE}"

    # glpi:database:install utilise mysqli (compatible MariaDB).
    # --default-language=fr_FR : interface GLPI en français dès le premier démarrage
    # --no-interaction : pas de prompt de confirmation
    # Sans --force : échoue proprement si les tables existent déjà
    php /var/www/html/bin/console glpi:database:install \
        --db-host="${MARIADB_HOST}" \
        --db-port="${MARIADB_PORT}" \
        --db-name="${MARIADB_DATABASE}" \
        --db-user="${MARIADB_USER}" \
        --db-password="${MARIADB_PASSWORD}" \
        --default-language=fr_FR \
        --no-interaction \
        2>&1

    # Corriger les permissions après l'install :
    # le CLI tourne en root et crée config_db.php, php-errors.log… avec owner root.
    # Apache (www-data) ne peut pas lire/écrire ces fichiers sans cette correction.
    # find -not -user évite de toucher les fichiers déjà propriété de www-data.
    find /var/www/html/files/ /var/www/html/config/ \
        -not -user www-data \
        -exec chown www-data:www-data {} \; 2>/dev/null || true

    # -------------------------------------------------------------------
    # Chargement des données de démonstration
    # seed_tickets.sql insère 5 catégories ITIL et 22 tickets répartis
    # sur 12 mois, pour que les dashboards Grafana affichent des données
    # dès le premier démarrage.
    # -------------------------------------------------------------------
    if [ -f /seed_tickets.sql ]; then
        echo "  Chargement des données de démonstration (tickets)..."
        mysql --ssl=0 -h "${MARIADB_HOST}" -P "${MARIADB_PORT}" \
              -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" \
              "${MARIADB_DATABASE}" < /seed_tickets.sql 2>&1 \
            && echo "  ✓ Données de démonstration insérées (22 tickets, 8 PC, 4 périphériques)." \
            || echo "  Avertissement : seed partiel (données peut-être déjà présentes)."
    fi

    echo ""
    echo "  ✓ GLPI prêt."
    echo "  Accès : http://localhost:8082  —  glpi / glpi"
    echo ""
fi

# ---------------------------------------------------------------------------
# [3/3] Démarrer Apache (remplace le processus courant via exec)
# ---------------------------------------------------------------------------
echo "[3/3] Démarrage d'Apache..."
exec "$@"
