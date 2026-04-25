# TP Intégration Logicielle — Stack GLPI · Grafana · Prometheus

**Module :** Intégration Logicielle — M2 ISIE IBAM  
**Enseignant :** Charles BATIONO  
**Auteurs :** [Prénom NOM] — [Prénom NOM]

> **Démarrage en une commande :**
> ```bash
> docker compose up -d
> ```

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Prérequis](#2-prérequis)
3. [Installation et démarrage](#3-installation-et-démarrage)
4. [Accès aux interfaces](#4-accès-aux-interfaces)
5. [Tableaux de bord Grafana](#5-tableaux-de-bord-grafana)
6. [Prometheus et PromQL](#6-prometheus-et-promql)
7. [Analyse de la base GLPI](#7-analyse-de-la-base-glpi)
8. [Arrêt et nettoyage](#8-arrêt-et-nettoyage)
9. [Difficultés rencontrées et solutions](#9-difficultés-rencontrées-et-solutions)
10. [Structure du projet](#10-structure-du-projet)

---

## 1. Vue d'ensemble

Ce projet déploie une **infrastructure ITSM complète** en environnement conteneurisé, composée de six services orchestrés par Docker Compose. L'objectif est de démontrer l'intégration cohérente de plusieurs technologies open source autour de GLPI, un système de gestion de parc informatique et de tickets d'incidents.

### Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Réseau Docker : glpi_network                      │
│                                                                        │
│   ┌─────────────┐   mysqli    ┌──────────────┐                        │
│   │  MariaDB    │◄────────────│     GLPI     │                        │
│   │  10.11      │             │   10.0.16    │                        │
│   │  :3306      │             │   :8082      │                        │
│   └─────────────┘             └──────────────┘                        │
│                                                                        │
│   ┌─────────────┐             ┌──────────────────────────────────┐    │
│   │ PostgreSQL  │◄────────────│            Grafana               │    │
│   │  15         │  datasource │           (latest)               │    │
│   │  :5432      │  secondaire │            :3000                 │    │
│   └─────────────┘             │                                  │    │
│                                │  ◄── datasource GLPI-MySQL      │    │
│   ┌─────────────┐             │  ◄── datasource Prometheus       │    │
│   │ Prometheus  │◄────────────│  ◄── datasource GLPI-PostgreSQL  │    │
│   │  (latest)   │  datasource └──────────────────────────────────┘    │
│   │  :9090      │◄─── scrape ─────────────────────┐                   │
│   └─────────────┘                                  │                   │
│                                            ┌────────────────┐         │
│                                            │   cAdvisor     │         │
│                                            │   (latest)     │         │
│                                            │   :8081        │         │
│                                            └────────────────┘         │
└──────────────────────────────────────────────────────────────────────┘
```

### Tableau des services

| # | Service | Image | Port hôte | Port interne | Rôle |
|---|---------|-------|-----------|--------------|------|
| 1 | **mariadb** | `mariadb:10.11` | — | 3306 | Base de données de GLPI |
| 2 | **postgres** | `postgres:15` | — | 5432 | Base auxiliaire (TP + Grafana) |
| 3 | **glpi** | image custom `php:8.2-apache` | **8082** | 80 | Application ITSM |
| 4 | **grafana** | `grafana/grafana:latest` | **3000** | 3000 | Tableaux de bord |
| 5 | **cadvisor** | `gcr.io/cadvisor/cadvisor:latest` | **8081** | 8080 | Métriques conteneurs |
| 6 | **prometheus** | `prom/prometheus:latest` | **9090** | 9090 | Collecte de métriques |

> **Sur le choix des bases de données :** Le sujet du TP impose PostgreSQL, mais GLPI
> utilise exclusivement le driver PHP `mysqli`, incompatible avec PostgreSQL au niveau
> protocolaire. MariaDB assure le fonctionnement réel de GLPI ; PostgreSQL est conservé
> comme base auxiliaire et datasource Grafana. L'analyse détaillée de cette contrainte
> se trouve en [section 9 — Difficultés rencontrées](#9-difficultés-rencontrées-et-solutions).

> **Image GLPI custom :** aucune image Docker publique de GLPI ne prend en charge
> l'installation automatique via CLI. Le `glpi/Dockerfile` construit une image
> `php:8.2-apache` avec GLPI 10.0.16 pré-installé et toutes les extensions PHP
> requises. La première exécution compile cette image (**~3-5 min**).

---

## 2. Prérequis

| Outil | Version minimale | Comment vérifier |
|-------|-----------------|-----------------|
| Docker Engine | 24.0+ | `docker --version` |
| Docker Compose | 2.20+ (plugin intégré) | `docker compose version` |
| RAM disponible | 4 Go recommandés | Gestionnaire de tâches / `free -h` |
| Espace disque | ~3 Go (images + volumes) | `docker system df` |
| OS | Windows 11, Ubuntu 22.04, macOS 13 | — |

> **Windows :** WSL2 doit être activé. Les volumes système (`/sys`, `/var/run`) sont
> exposés à cAdvisor via le backend WSL2 de Docker Desktop.
>
> **Proxy d'entreprise :** si Docker ne peut pas joindre Docker Hub, configurer un
> miroir dans *Docker Desktop → Settings → Docker Engine* :
> ```json
> { "registry-mirrors": ["https://mirror.gcr.io"] }
> ```

---

## 3. Installation et démarrage

### Étape 1 — Récupérer le projet

```bash
git clone <url-du-depot>
cd tp-integration
```

### Étape 2 — Configurer les variables d'environnement

```bash
cp .env.example .env
```

Le fichier `.env` contient les mots de passe de toutes les bases et services. Les valeurs par défaut fonctionnent en développement local. En production, **remplacer chaque `changeme`** par un mot de passe fort.

```ini
# MariaDB — base de données de GLPI
MARIADB_DATABASE=glpi
MARIADB_USER=glpi_user
MARIADB_PASSWORD=changeme
MARIADB_ROOT_PASSWORD=changeme_root

# PostgreSQL — base auxiliaire (TP)
POSTGRES_DB=glpi_tp
POSTGRES_USER=postgres_user
POSTGRES_PASSWORD=changeme

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=changeme

# Prometheus — durée de rétention des métriques
PROMETHEUS_RETENTION=15d
```

> ⚠ Le fichier `.env` est exclu du dépôt Git par `.gitignore`. Ne jamais le committer.

### Étape 3 — Démarrer la stack

```bash
docker compose up -d
```

**Ce qui se passe en coulisses lors du premier démarrage :**

1. Docker construit l'image GLPI custom à partir de `glpi/Dockerfile` (~3-5 min)
2. MariaDB démarre et initialise sa base de données
3. Le healthcheck MariaDB (`--innodb_initialized`) attend que le moteur soit opérationnel
4. Le conteneur GLPI démarre ; `entrypoint.sh` exécute automatiquement :
   ```bash
   php bin/console glpi:database:install \
       --db-host=mariadb --db-name=glpi \
       --db-user=glpi_user \
       --default-language=fr_FR \
       --no-interaction
   ```
5. Les permissions des fichiers créés par le CLI (root) sont corrigées pour `www-data`
6. `glpi/seed_tickets.sql` est chargé automatiquement — **données de démo pré-insérées** :
   - 5 catégories ITIL (Réseau, Matériel, Logiciel, Sécurité, Accès et droits)
   - 22 tickets répartis sur 12 mois (statuts 1→6, types incident/demande)
   - 8 ordinateurs du parc affectés à 3 utilisateurs
   - 4 périphériques (imprimante, scanner, écran, docking station)
   - 41 liaisons tickets↔utilisateurs (demandeurs + techniciens assignés)
7. Apache démarre — GLPI est accessible sur http://localhost:8082 (login : `glpi` / `glpi`)

Les redémarrages suivants sont quasi-instantanés : `config_db.php` est présent dans le volume `glpi_config`, l'étape d'installation est ignorée.

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #1 :
     Terminal affichant "docker compose logs glpi" avec les trois étapes visibles :
       [1/3] MariaDB est joignable.
       [2/3] Installation done.
       [3/3] Démarrage d'Apache...
     Prouve que l'installation automatique fonctionne sans intervention manuelle.
-->

### Étape 4 — Vérifier l'état des services

```bash
docker compose ps
```

Résultat attendu :

```
NAME              IMAGE                             STATUS
glpi_app          integration-logi-glpi             Up (running)
glpi_cadvisor     gcr.io/cadvisor/cadvisor:latest   Up (healthy)
glpi_grafana      grafana/grafana:latest            Up (running)
glpi_mariadb      mariadb:10.11                     Up (healthy)
glpi_postgres     postgres:15                       Up (healthy)
glpi_prometheus   prom/prometheus:latest            Up (running)
```

MariaDB et PostgreSQL affichent `healthy` grâce à leurs healthchecks respectifs :
- MariaDB : `healthcheck.sh --connect --innodb_initialized`
- PostgreSQL : `pg_isready -U postgres_user -d glpi_tp`

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #2 :
     Résultat de "docker compose ps" dans le terminal,
     tous les services affichant "Up" ou "healthy".
-->

---

## 4. Accès aux interfaces

| Service | URL | Identifiants |
|---------|-----|-------------|
| **GLPI** | http://localhost:8082 | `glpi` / `glpi` |
| **Grafana** | http://localhost:3000 | `admin` / valeur `GF_SECURITY_ADMIN_PASSWORD` dans `.env` |
| **Prometheus** | http://localhost:9090 | — (accès libre) |
| **cAdvisor** | http://localhost:8081 | — (accès libre) |

> **GLPI — données pré-chargées :** `glpi/seed_tickets.sql` est exécuté automatiquement
> au premier démarrage. Les dashboards Grafana affichent des données réelles dès la
> connexion — aucune saisie manuelle nécessaire. Voir le tableau récapitulatif en
> [section 3](#3-installation-et-démarrage) pour le détail des objets insérés.
>
> **Langue :** GLPI démarre en **français** (`fr_FR`), configuré via l'option
> `--default-language=fr_FR` du CLI d'installation.
>
> **Sécurité :** Changer le mot de passe `glpi/glpi` immédiatement après la première
> connexion — GLPI affiche une bannière d'avertissement à cet effet.

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #3 :
     Page d'accueil GLPI après connexion (tableau de bord, menu latéral visible,
     statistiques affichées). Montre que l'application est pleinement fonctionnelle.
-->

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #4 :
     Administration > Informations système dans GLPI.
     Affiche : version GLPI 10.0.16, PHP 8.2.x, MariaDB 10.11, extensions actives.
     Confirme visuellement la configuration technique déployée.
-->

---

## 5. Tableaux de bord Grafana

Grafana est entièrement pré-configuré au démarrage : **trois datasources** et **deux dashboards** sont provisionnés automatiquement depuis les fichiers YAML et JSON du dépôt. Aucune manipulation dans l'interface n'est nécessaire.

### Datasources provisionnées

| Datasource | Type | UID fixe | Cible réseau | Rôle |
|-----------|------|----------|-------------|------|
| `GLPI-MySQL` | MySQL | `GLPI-MySQL` | `mariadb:3306` | Données GLPI — **défaut** |
| `Prometheus` | Prometheus | `Prometheus` | `prometheus:9090` | Métriques infrastructure |
| `GLPI-PostgreSQL` | PostgreSQL | `GLPI-PostgreSQL` | `postgres:5432` | Démonstration TP |

Les UIDs sont déclarés explicitement dans les fichiers YAML de provisioning. Sans UID fixe, Grafana génère un identifiant aléatoire à chaque redémarrage, ce qui brise les références des dashboards JSON et affiche "Datasource not found" dans chaque panel.

### Dashboard 1 — GLPI Gestion du parc informatique

Dashboard par défaut, accessible sur http://localhost:3000. Il interroge MariaDB/MySQL pour afficher les données GLPI en temps réel (rafraîchissement toutes les 30 s).

| Panel | Type de visualisation | Logique de la requête |
|-------|-----------------------|----------------------|
| Tickets ouverts | Compteur | `COUNT(*) WHERE status NOT IN (5,6)` |
| Tickets créés aujourd'hui | Compteur | `COUNT(*) WHERE DATE(date_creation) = CURDATE()` |
| Équipements enregistrés | Compteur | Somme `computers` + `peripherals` non supprimés |
| Résolus ce mois | Compteur | `COUNT(*) WHERE status IN (5,6)` depuis le 1er du mois |
| Répartition par statut | Camembert | `GROUP BY status` avec libellés ITIL |
| Évolution 30 jours | Série temporelle | `GROUP BY DATE(date_creation)` |
| Top 5 catégories | Barres horizontales | `JOIN glpi_itilcategories … LIMIT 5` |
| 20 derniers tickets | Tableau coloré | `ORDER BY date_creation DESC LIMIT 20` |
| Tickets par priorité | Barres verticales | `GROUP BY priority` (tickets ouverts uniquement) |
| Tickets par mois — 12 mois | Série temporelle | `GROUP BY DATE_FORMAT(date_creation, '%Y-%m-01')` |

> GLPI 10.x stocke toutes ses dates (`date_creation`, `date_mod`, `solvedate`…) en colonnes
> **DATETIME/TIMESTAMP** natives — et non comme entiers Unix. Les fonctions `DATE()`,
> `DATE_FORMAT()` et `DATE_SUB()` s'appliquent directement, sans `FROM_UNIXTIME()`.
> Voir [section 9](#9-difficultés-rencontrées-et-solutions) pour le détail de cette découverte.

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #5 :
     Dashboard Grafana "GLPI — Gestion du parc informatique" avec les 10 panels visibles
     (dézoomer si nécessaire). Créer au préalable quelques tickets dans GLPI pour que
     les compteurs et graphiques affichent des valeurs non nulles.
-->

### Dashboard 2 — Monitoring Infrastructure

Interroge Prometheus (métriques collectées par cAdvisor depuis les cgroups Docker).

| Panel | Requête PromQL |
|-------|---------------|
| CPU par conteneur (%) | `rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100` |
| Mémoire par conteneur (Mo) | `container_memory_usage_bytes{name!=""} / 1024 / 1024` |
| Réseau entrant | `rate(container_network_receive_bytes_total{name!=""}[5m])` |
| Réseau sortant | `rate(container_network_transmit_bytes_total{name!=""}[5m])` |

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #6 :
     Dashboard "Monitoring Infrastructure" avec les courbes CPU et mémoire
     des six conteneurs en temps réel. Montre l'intégration cAdvisor → Prometheus → Grafana.
-->

---

## 6. Prometheus et PromQL

### Targets configurées

Accéder à http://localhost:9090/targets pour visualiser l'état des cibles de scrape :

| Job | Target | Statut attendu | Raison |
|-----|--------|---------------|--------|
| `prometheus` | `localhost:9090` | **UP** | Auto-scrape de Prometheus |
| `cadvisor` | `cadvisor:8080` | **UP** | Métriques Docker en temps réel |
| `glpi` | `glpi:80` | **DOWN** | GLPI n'expose pas `/metrics` nativement |

La cible `glpi` est configurée intentionnellement bien qu'elle soit DOWN. Cela démontre la gestion multi-cibles dans Prometheus et la distinction entre une cible inaccessible et une erreur de configuration.

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #7 :
     Page http://localhost:9090/targets affichant les trois jobs :
     "prometheus" UP (vert), "cadvisor" UP (vert), "glpi" DOWN (rouge).
-->

### Différence entre `scrape_interval` et `evaluation_interval`

Ces deux paramètres sont tous deux fixés à **15 s** dans `prometheus/prometheus.yml` :

- **`scrape_interval` (15 s)** — fréquence à laquelle Prometheus interroge (*scrape*) chaque cible pour récupérer ses métriques. C'est la **résolution temporelle** des données stockées. Une valeur de 15 s signifie un point de mesure toutes les 15 secondes.

- **`evaluation_interval` (15 s)** — fréquence à laquelle Prometheus évalue les *règles d'alerte* définies dans `rule_files`. Ces règles peuvent générer des séries dérivées ou déclencher des alertes vers Alertmanager.

Les deux valeurs sont alignées délibérément : évaluer des alertes plus souvent que le scrape serait inutile — les données n'auraient pas changé entre deux évaluations.

### Requête PromQL expliquée

```promql
rate(container_cpu_usage_seconds_total{name!=""}[5m])
```

| Élément | Signification |
|---------|---------------|
| `container_cpu_usage_seconds_total` | Compteur cumulatif du temps CPU consommé, en secondes |
| `{name!=""}` | Filtre les conteneurs nommés ; exclut les cgroups système sans nom |
| `[5m]` | Fenêtre glissante de 5 min pour lisser les pics ponctuels |
| `rate(...)` | Taux d'augmentation par seconde — `1.0` équivaut à 100 % d'un cœur |

Une valeur de `0.05` signifie que le conteneur consomme 5 % d'un cœur. Multiplier par 100 donne le pourcentage d'utilisation CPU affiché dans le dashboard.

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #8 :
     Onglet Graph de Prometheus (http://localhost:9090/graph) avec la requête
     rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100
     et les courbes de chaque conteneur affichées.
-->

---

## 7. Analyse de la base GLPI

L'analyse complète du schéma de base de données est disponible dans [analyse/analyse_bdd_glpi.md](analyse/analyse_bdd_glpi.md). Elle couvre cinq questions :

- **Q1** — Les 10 tables principales et leur rôle dans l'architecture GLPI
- **Q2** — Comptage des tickets par statut avec libellés ITIL (window functions MariaDB)
- **Q3** — Évolution mensuelle sur 12 mois glissants
- **Q4** — Équipements associés à un utilisateur (deux méthodes de jointure)
- **Q5** — Architecture SLA (`glpi_slms` ↔ `glpi_tickets`) et analyse du respect des délais

Pour exécuter les requêtes directement dans le conteneur :

```bash
docker compose exec mariadb mysql -u glpi_user -p glpi
# → saisir la valeur de MARIADB_PASSWORD dans .env
```

```sql
-- Vérifier que les tables GLPI sont bien créées
SELECT table_name,
       ROUND((data_length + index_length) / 1024, 0) AS taille_ko,
       table_rows AS lignes_approx
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC
LIMIT 15;
```

<!-- 📸 CAPTURE D'ÉCRAN SUGGÉRÉE #9 :
     Terminal affichant le résultat de la requête ci-dessus dans le shell MariaDB.
     Les tables glpi_tickets, glpi_computers, glpi_users, etc. doivent apparaître.
     Prouve que la base GLPI est correctement initialisée.
-->

---

## 8. Arrêt et nettoyage

### Arrêt simple — données conservées

```bash
docker compose down
```

Les volumes Docker (`mariadb_data`, `glpi_config`, `grafana_data`, etc.) sont conservés. Le prochain `docker compose up -d` redémarre la stack sans réinstaller GLPI.

### Redémarrage d'un service individuel

```bash
docker compose restart glpi
docker compose restart grafana
```

### Consultation des logs

```bash
docker compose logs -f glpi          # Suivre l'installation en temps réel
docker compose logs -f mariadb       # Logs MariaDB
docker compose logs --tail=50 grafana
```

### Arrêt complet avec suppression des données

```bash
# ⚠ DESTRUCTIF — supprime tous les volumes (MariaDB, Grafana, Prometheus…)
docker compose down -v
```

Le prochain démarrage repart de zéro : reconstruction de l'image GLPI, réinstallation de la base, réinitialisation des dashboards Grafana.

### Reconstruction forcée de l'image GLPI

À effectuer si `glpi/Dockerfile` ou `glpi/entrypoint.sh` est modifié :

```bash
docker compose build --no-cache glpi
docker compose up -d
```

---

## 9. Difficultés rencontrées et solutions

### Difficulté 1 — Incompatibilité fondamentale GLPI + PostgreSQL

**Contexte :** le sujet du TP indique PostgreSQL comme base de données. La documentation officielle de GLPI 10.x mentionne effectivement PostgreSQL parmi les bases supportées. Ces deux éléments laissaient supposer une intégration directe possible.

**Problème découvert :** GLPI utilise exclusivement le driver PHP `mysqli` pour toutes ses opérations de base de données, y compris le CLI d'installation et l'installeur web :

```bash
# Vérification dans le code source de l'image GLPI
grep -n "new mysqli\|DBmysql" install/install.php
# → $mysqli = new mysqli($host, $user, $pass, $db);
```

`mysqli` implémente le protocole binaire MySQL. Ce protocole est fondamentalement différent du protocole `libpq` de PostgreSQL — les deux sont incompatibles au niveau réseau. Résultat observé :

```
Installeur web   → "Connection refused" (port 5432 rejeté par un driver MySQL)
CLI              → "(2006) MySQL server has gone away"
```

**Solution :** MariaDB 10.11 est utilisé comme base de données de GLPI (protocole MySQL, totalement compatible avec `mysqli`). L'installation est automatisée via le CLI GLPI dans `entrypoint.sh`. PostgreSQL est conservé dans la stack comme base auxiliaire et datasource Grafana, satisfaisant ainsi l'exigence pédagogique.

| Base | Qui s'y connecte | Contenu |
|------|-----------------|---------|
| **MariaDB 10.11** | GLPI (application complète) | Tickets, utilisateurs, équipements, config |
| **PostgreSQL 15** | Grafana (datasource secondaire) | Base vide `glpi_tp` — présence pédagogique |

---

### Difficulté 2 — Permissions root sur les fichiers créés par le CLI GLPI

**Problème :** `glpi:database:install` s'exécute en `root` dans le conteneur (comportement Docker standard). Il crée `config_db.php` et `files/_log/php-errors.log` avec owner `root:root`. Apache tourne en `www-data` — il ne peut pas écrire dans ces fichiers. GLPI affiche à l'ouverture :

```
An error has occurred, but the trace of this error could not be recorded
because of a problem accessing the log file.
```

**Solution :** après l'installation CLI, `entrypoint.sh` corrige les propriétaires avec un ciblage précis :

```bash
find /var/www/html/files/ /var/www/html/config/ \
    -not -user www-data \
    -exec chown www-data:www-data {} \;
```

`find -not -user` ne traite que les fichiers dont le propriétaire n'est pas encore `www-data`, ce qui évite de recourir à un `chown -R` aveugle sur l'ensemble de l'arborescence.

---

### Difficulté 3 — UIDs Grafana aléatoires → panels "Datasource not found"

**Problème :** sans `uid:` explicite dans les fichiers YAML de provisioning, Grafana génère un identifiant aléatoire à chaque redémarrage. Les dashboards JSON contiennent des UIDs en dur (`"GLPI-MySQL"`, `"Prometheus"`) — la correspondance est impossible et tous les panels affichent "Datasource not found".

**Solution :** déclaration explicite des UIDs dans chaque fichier de provisioning :

```yaml
# grafana/provisioning/datasources/mysql.yml
datasources:
  - name: GLPI-MySQL
    uid: "GLPI-MySQL"   # ← identifiant stable entre les redémarrages
```

Les dashboards JSON référencent exactement ces valeurs.

---

### Difficulté 4 — Variables d'environnement non transmises à Grafana

**Problème :** les fichiers YAML de provisioning utilisent `${MARIADB_DATABASE}`, `${POSTGRES_PASSWORD}`, etc. Docker Compose résout ces variables uniquement si elles sont déclarées dans la section `environment:` du service Grafana. Sans cette déclaration, elles se résolvent en chaîne vide — la datasource est créée mais avec des paramètres de connexion vides.

**Solution :** déclaration explicite dans `docker-compose.yml` :

```yaml
grafana:
  environment:
    MARIADB_DATABASE: ${MARIADB_DATABASE}
    MARIADB_USER: ${MARIADB_USER}
    MARIADB_PASSWORD: ${MARIADB_PASSWORD}
    POSTGRES_DB: ${POSTGRES_DB}
    POSTGRES_USER: ${POSTGRES_USER}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

---

### Difficulté 5 — `/dev/kmsg` absent sur Windows et macOS

**Problème :** la directive `devices: - /dev/kmsg` dans la configuration de cAdvisor provoque `no such file or directory` sur Windows (WSL2) et macOS — ce device kernel Linux n'existe pas dans ces environnements.

**Solution :** suppression de la section `devices:`. cAdvisor collecte les métriques CPU, mémoire et réseau via les cgroups sans nécessiter `/dev/kmsg`.

---

### Difficulté 6 — Port 8080 déjà utilisé sur la machine hôte

**Problème :** sur Windows, le port 8080 était occupé par une autre application, empêchant le binding Docker.

**Solution :** redirection vers le port **8082** dans `docker-compose.yml` (`"8082:80"`).

---

### Difficulté 7 — `pull access denied` sur l'image GLPI custom

**Problème :** avec les directives `build:` et `image: glpi-custom:...` combinées, Docker tentait de puller l'image depuis Docker Hub avant de la construire localement.

**Solution :** suppression du champ `image:` et ajout de `pull_policy: build`.

---

### Difficulté 8 — Conversion SQL PostgreSQL → MySQL et type des dates GLPI

**Problème :** deux obstacles liés aux requêtes SQL des dashboards Grafana.

**(a) Syntaxe PostgreSQL incompatible avec MariaDB.** Les premières requêtes utilisaient la syntaxe PostgreSQL :

| Syntaxe PostgreSQL | Syntaxe MySQL/MariaDB équivalente |
|-------------------|------------------------------------|
| `DATE_TRUNC('day', ts)` | `DATE(ts)` |
| `DATE_TRUNC('month', ts)` | `DATE_FORMAT(ts, '%Y-%m-01')` |
| `ts >= NOW() - INTERVAL '30 days'` | `ts >= DATE_SUB(NOW(), INTERVAL 30 DAY)` |
| `to_char(ts, 'DD/MM/YYYY HH24:MI')` | `DATE_FORMAT(ts, '%d/%m/%Y %H:%i')` |
| `'a' \|\| col::text \|\| 'b'` | `CONCAT('a', col, 'b')` |

**(b) `date_creation` est un DATETIME natif, pas un entier Unix.** L'hypothèse initiale était que GLPI stocke ses dates comme entiers Unix (comme certains vieux CMS). La commande `DESCRIBE glpi_tickets` a révélé que `date_creation` est de type `timestamp` (DATETIME natif MySQL). Cela a rendu `FROM_UNIXTIME()` et `UNIX_TIMESTAMP()` inutiles — et incorrects (ils auraient interprété un timestamp MySQL comme un nombre de secondes). Toutes les requêtes ont été corrigées pour opérer directement sur le DATETIME : `DATE(date_creation)`, `DATE_FORMAT(date_creation, '%Y-%m')`, `date_creation >= DATE_SUB(NOW(), INTERVAL 30 DAY)`.

---

## 10. Structure du projet

```
tp-integration/
│
├── docker-compose.yml              ← Orchestration des 6 services
├── .env                            ← Secrets (exclu du dépôt Git)
├── .env.example                    ← Template de configuration à copier
├── .gitignore                      ← Exclusion de .env et fichiers temporaires
├── README.md                       ← Ce fichier
│
├── glpi/
│   ├── Dockerfile                  ← Image PHP 8.2 + Apache + GLPI 10.0.16 + extensions
│   ├── entrypoint.sh               ← Installation automatique via CLI au 1er démarrage
│   └── seed_tickets.sql            ← Données de démo : 5 catégories, 22 tickets, 8 PC,
│                                      4 périphériques, 41 liaisons tickets↔utilisateurs
│
├── prometheus/
│   └── prometheus.yml              ← Scrape configs : prometheus, cadvisor, glpi
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   ├── mysql.yml           ← Datasource MariaDB/GLPI (uid fixe, isDefault: true)
│   │   │   ├── postgres.yml        ← Datasource PostgreSQL (uid fixe, isDefault: false)
│   │   │   └── prometheus.yml      ← Datasource Prometheus (uid fixe)
│   │   └── dashboards/
│   │       └── dashboards.yml      ← Déclaration du répertoire de dashboards
│   └── dashboards/
│       ├── glpi_dashboard.json     ← 10 panels ITSM (datasource MySQL)
│       └── monitoring_dashboard.json ← Panels infra Docker (datasource Prometheus)
│
└── analyse/
    └── analyse_bdd_glpi.md         ← Analyse schéma GLPI — Q1 à Q5 (SQL MySQL/MariaDB)
```

---

*Projet réalisé dans le cadre du module Intégration Logicielle — M2 ISIE IBAM.*  
*Stack testée sur Windows 11 (Docker Desktop 4.x + WSL2) et Ubuntu 22.04.*
