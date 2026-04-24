#!/bin/bash
# =============================================================================
# Script d'entrée GLPI — initialisation automatique avec PostgreSQL
#
# Logique :
#   1. Attendre que PostgreSQL accepte les connexions (via netcat TCP)
#   2. Si config/config_db.php absent → premier démarrage : lancer l'installeur
#   3. Si config/config_db.php présent → démarrage suivant : lancer le updater
#   4. Démarrer Apache
#
# Pourquoi vérifier config_db.php ?
#   Ce fichier est créé par GLPI après une installation réussie. Sa présence
#   indique que la base est déjà initialisée, ce qui évite de relancer
#   glpi:database:install sur une base existante (provoque une erreur).
# =============================================================================

set -e

GLPI_DIR="/var/www/html"
CONFIG_DB="${GLPI_DIR}/config/config_db.php"

# Valeurs par défaut (surchargées par les variables d'environnement du conteneur)
DB_HOST="${GLPI_DB_HOST:-postgres}"
DB_PORT="${GLPI_DB_PORT:-5432}"
DB_NAME="${GLPI_DB_NAME:-glpi}"
DB_USER="${GLPI_DB_USER:-glpi_user}"
DB_PASS="${GLPI_DB_PASSWORD:-changeme}"

echo "============================================================"
echo " GLPI — Démarrage du conteneur"
echo " Cible PostgreSQL : ${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "============================================================"

# ---------------------------------------------------------------------------
# Étape 1 : Attendre que PostgreSQL soit joignable (connectivité TCP)
# La condition service_healthy de Docker Compose garantit déjà que PostgreSQL
# est prêt, mais cette boucle protège des rares cas de race condition.
# ---------------------------------------------------------------------------
echo "[1/3] Attente de PostgreSQL à ${DB_HOST}:${DB_PORT}..."
TIMEOUT=60
while ! nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; do
    TIMEOUT=$((TIMEOUT - 1))
    if [ "${TIMEOUT}" -le 0 ]; then
        echo "ERREUR : Impossible de joindre PostgreSQL après 60 secondes."
        echo "Vérifiez que le service 'postgres' est healthy avec : docker compose ps"
        exit 1
    fi
    echo "  PostgreSQL pas encore disponible, nouvelle tentative dans 2s... (${TIMEOUT}s restantes)"
    sleep 2
done
echo "  PostgreSQL est joignable."

# ---------------------------------------------------------------------------
# Étape 2 : Installation ou mise à jour de la base GLPI
# ---------------------------------------------------------------------------
if [ ! -f "${CONFIG_DB}" ]; then
    echo "[2/3] Premier démarrage détecté — installation de la base GLPI..."
    echo "  Cela peut prendre 1 à 2 minutes..."

    # glpi:database:install crée toutes les tables GLPI dans PostgreSQL
    # et génère le fichier config/config_db.php avec les paramètres de connexion.
    php "${GLPI_DIR}/bin/console" glpi:database:install \
        --db-host="${DB_HOST}" \
        --db-port="${DB_PORT}" \
        --db-name="${DB_NAME}" \
        --db-user="${DB_USER}" \
        --db-password="${DB_PASS}" \
        --no-interaction \
        2>&1

    # Restaurer les permissions après la création de config_db.php
    chown -R www-data:www-data \
        "${GLPI_DIR}/config" \
        "${GLPI_DIR}/files" \
        "${GLPI_DIR}/plugins" \
        "${GLPI_DIR}/marketplace" 2>/dev/null || true

    echo "  Installation terminée avec succès."
else
    echo "[2/3] Base déjà configurée — vérification des mises à jour de schéma..."

    # glpi:database:update applique les migrations manquantes (upgrade de version)
    # Le flag --allow-unstable accepte les migrations en cours de stabilisation.
    php "${GLPI_DIR}/bin/console" glpi:database:update \
        --no-interaction \
        --allow-unstable \
        2>&1 || echo "  Aucune mise à jour nécessaire."
fi

# ---------------------------------------------------------------------------
# Étape 3 : Démarrer Apache (remplace le processus courant via exec)
# ---------------------------------------------------------------------------
echo "[3/3] Démarrage d'Apache..."
exec "$@"
