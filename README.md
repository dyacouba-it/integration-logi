# TP Intégration Logicielle — Stack GLPI + Grafana + Prometheus

**Module :** Intégration Logicielle — M2 ISIE IBAM  
**Enseignant :** Charles BATIONO  
**Auteurs :** [Prénom NOM] — [Prénom NOM] *(compléter avec les noms du groupe)*

---

## Présentation du projet

Ce projet déploie une infrastructure d'entreprise complète en **une seule commande** :

```bash
docker compose up -d
```

> **Pourquoi une image GLPI custom ?** Les images publiques (`diouxx/glpi`, `elestio/glpi`) sont
> construites pour MySQL/MariaDB uniquement. GLPI 10.x supporte officiellement PostgreSQL 12+,
> mais nécessite les extensions PHP `pdo_pgsql`/`pgsql` absentes de ces images.
> Le `glpi/Dockerfile` de ce projet construit l'image correcte avec PostgreSQL.
> La première exécution compile cette image (~2-3 min).

### Architecture déployée

```
┌─────────────────────────────────────────────────────────────┐
│                    Réseau Docker : glpi_network              │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌────────────────────┐    │
│  │PostgreSQL│◄───│   GLPI   │    │      Grafana        │    │
│  │  :5432   │    │  :8080   │    │       :3000         │    │
│  └──────────┘    └──────────┘    └────────┬───────────┘    │
│       ▲                                    │                 │
│       │ (datasource)                       │ (datasource)   │
│       └───────────────────────────────────►│                 │
│                                            │                 │
│  ┌──────────┐    ┌──────────┐              │                 │
│  │cAdvisor  │◄───│Prometheus│◄─────────────┘                │
│  │  :8081   │    │  :9090   │                               │
│  └──────────┘    └──────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

| Service | Rôle | Port |
|---------|------|------|
| **PostgreSQL 15** | Base de données de GLPI | 5432 (interne) |
| **GLPI** | Gestion de parc informatique (ITSM) | 8080 |
| **Grafana** | Tableaux de bord et visualisation | 3000 |
| **cAdvisor** | Métriques Docker temps réel | 8081 |
| **Prometheus** | Collecte et stockage des métriques | 9090 |

---

## Prérequis

| Outil | Version minimale | Vérification |
|-------|-----------------|--------------|
| Docker | 24.0+ | `docker --version` |
| Docker Compose | 2.20+ (plugin) | `docker compose version` |
| RAM disponible | 4 Go recommandés | — |
| OS testé | Windows 11 / Ubuntu 22.04 / macOS 13 | — |

> **Note Windows :** cAdvisor nécessite WSL2 activé. Les volumes `/sys`, `/var/run` etc. sont exposés via WSL2.

---

## Instructions de démarrage

### 1. Cloner le dépôt

```bash
git clone <url-du-depot>
cd tp-integration
```

### 2. Créer le fichier de configuration

```bash
# Copier l'exemple et adapter les mots de passe
cp .env.example .env

# Éditer .env si nécessaire (les valeurs par défaut fonctionnent en dev)
```

### 3. Démarrer la stack

```bash
docker compose up -d
```

> **Premier démarrage** : Docker compile d'abord l'image GLPI custom (**~2-3 min**), puis GLPI
> initialise sa base de données dans PostgreSQL (**1-2 min supplémentaires**).
> Suivre la progression :
> ```bash
> docker compose logs -f glpi
> ```
> Attendre le message `[3/3] Démarrage d'Apache...` avant d'accéder à l'interface.
> Les redémarrages suivants sont instantanés (l'image et la base sont déjà prêtes).

### 4. Vérifier que tous les services sont démarrés

```bash
docker compose ps
```

Tous les services doivent afficher `running` (ou `healthy` pour PostgreSQL).

### 5. Accéder aux interfaces

| Service | URL | Commentaire |
|---------|-----|-------------|
| GLPI | http://localhost:8080 | Interface ITSM principale |
| Grafana | http://localhost:3000 | Tableaux de bord |
| Prometheus | http://localhost:9090 | Interface PromQL |
| cAdvisor | http://localhost:8081 | Métriques conteneurs |

---

## Identifiants par défaut

### GLPI
| Champ | Valeur |
|-------|--------|
| URL | http://localhost:8080 |
| Utilisateur | `glpi` |
| Mot de passe | `glpi` |

> Changer le mot de passe immédiatement après la première connexion.

### Grafana
| Champ | Valeur |
|-------|--------|
| URL | http://localhost:3000 |
| Utilisateur | `admin` (ou valeur `GF_SECURITY_ADMIN_USER` dans `.env`) |
| Mot de passe | Valeur `GF_SECURITY_ADMIN_PASSWORD` dans `.env` |

---

## Vérifier Prometheus

Accéder à http://localhost:9090/targets pour vérifier que les cibles sont `UP` :

```
Cible             | Statut attendu | Notes
prometheus        | UP             | Auto-scrape
cadvisor          | UP             | Métriques Docker
glpi              | DOWN/UP        | GLPI n'expose pas /metrics nativement
```

---

## Arrêt et nettoyage

### Arrêt simple (données conservées)
```bash
docker compose down
```

### Arrêt complet avec suppression des données
```bash
# ATTENTION : supprime toutes les données PostgreSQL, Grafana et Prometheus
docker compose down -v
```

### Redémarrage d'un seul service
```bash
docker compose restart glpi
```

### Voir les logs d'un service
```bash
docker compose logs -f postgres
docker compose logs -f glpi
```

---

## Réponses aux questions PromQL — Partie 4

### Targets configurés et leur statut

Après démarrage, http://localhost:9090/targets affiche :

| Job | Target | Statut |
|-----|--------|--------|
| `prometheus` | `localhost:9090` | UP |
| `cadvisor` | `cadvisor:8080` | UP |
| `glpi` | `glpi:80` | DOWN (pas d'endpoint /metrics natif dans GLPI) |

### Différence entre `scrape_interval` et `evaluation_interval`

- **`scrape_interval` (15s)** : fréquence à laquelle Prometheus interroge (*scrape*) chaque cible pour collecter ses métriques. C'est la résolution temporelle des données stockées.

- **`evaluation_interval` (15s)** : fréquence à laquelle Prometheus évalue les *règles d'alerte* définies dans `rule_files`. Ces règles calculent des métriques dérivées ou déclenchent des alertes.

> Les deux sont fixés à 15s dans notre configuration pour avoir une cohérence entre la collecte et l'évaluation. Une `evaluation_interval` plus courte que `scrape_interval` n'a pas de sens car les données n'auraient pas changé.

### Explication de la requête PromQL

```promql
rate(container_cpu_usage_seconds_total{name!=""}[5m])
```

**Décomposition :**

| Élément | Signification |
|---------|---------------|
| `container_cpu_usage_seconds_total` | Compteur cumulatif du temps CPU utilisé (en secondes) par conteneur |
| `{name!=""}` | Filtre : exclure les conteneurs sans nom (processus système, cgroups hôte) |
| `[5m]` | Fenêtre glissante de 5 minutes pour le calcul du taux |
| `rate(...)` | Calcule le taux d'augmentation moyen par seconde sur la fenêtre — en CPU, `rate = 1.0` signifie 100% d'un cœur utilisé |

**Résultat** : la valeur retournée est le **nombre de cœurs CPU utilisés par seconde** pour chaque conteneur. Multiplier par 100 donne un pourcentage. Un conteneur avec `rate = 0.05` utilise 5% d'un cœur.

---

## Difficultés rencontrées et solutions apportées

### 1. Incompatibilité images GLPI publiques + PostgreSQL
**Problème :** `diouxx/glpi` et toutes les images GLPI disponibles sur Docker Hub sont construites pour MySQL/MariaDB. Elles ignorent toute configuration PostgreSQL et utilisent les variables `MARIADB_*`. L'extension PHP `pdo_pgsql` est absente, rendant toute connexion à PostgreSQL impossible.  
**Solution :** Construction d'une image custom (`glpi/Dockerfile`) basée sur `php:8.2-apache` avec installation manuelle de GLPI 10.0.16 et des extensions `pdo_pgsql`/`pgsql`. L'initialisation de la base se fait via `php bin/console glpi:database:install` au premier démarrage.

### 2. UIDs Grafana non définis → panels "Datasource not found"
**Problème :** Sans champ `uid:` explicite dans les fichiers de provisioning, Grafana génère des UIDs aléatoires à chaque démarrage. Les dashboards JSON référencent des UIDs fixes (`"GLPI-PostgreSQL"`, `"Prometheus"`) qui ne correspondent jamais aux UIDs générés.  
**Solution :** Ajout de `uid: "GLPI-PostgreSQL"` et `uid: "Prometheus"` dans les fichiers YAML de provisioning, avec correspondance exacte dans les dashboards.

### 3. Variables PostgreSQL manquantes dans le conteneur Grafana
**Problème :** `postgres.yml` utilise `${POSTGRES_DB}`, `${POSTGRES_USER}`, `${POSTGRES_PASSWORD}`, mais ces variables n'étaient pas déclarées dans la section `environment:` du service Grafana. Elles se résolvaient en chaînes vides, rendant la datasource inutilisable.  
**Solution :** Ajout explicite de `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` dans les variables d'environnement du conteneur Grafana.

### 4. `/dev/kmsg` absent sur Windows/macOS → cAdvisor crash
**Problème :** La directive `devices: - /dev/kmsg` provoque l'erreur `no such file or directory` sur Windows (WSL2) et macOS car ce device kernel n'existe pas dans ces environnements.  
**Solution :** Suppression de la section `devices:`. cAdvisor fonctionne sans accès à `/dev/kmsg` pour les métriques CPU, RAM et réseau nécessaires au dashboard.

### 5. Volume `config/` manquant → réinstallation en boucle
**Problème :** Sans volume persistant pour `config_db.php`, chaque redémarrage du conteneur GLPI déclenchait une réinstallation sur une base déjà initialisée, causant l'erreur "tables already exist".  
**Solution :** Ajout du volume nommé `glpi_config:/var/www/html/config`. Le script `entrypoint.sh` vérifie la présence de `config_db.php` pour choisir entre installation (première fois) et mise à jour (redémarrages).

---

## Structure du projet

```
tp-integration/
├── docker-compose.yml               ← Orchestration de toute la stack
├── .env                             ← Variables sensibles (non versionné)
├── .env.example                     ← Template à copier
├── .gitignore
├── README.md                        ← Ce fichier
├── glpi/
│   ├── Dockerfile                   ← Image GLPI custom avec support PostgreSQL
│   └── entrypoint.sh                ← Init automatique de la base au 1er démarrage
├── prometheus/
│   └── prometheus.yml               ← Configuration scrape Prometheus
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   ├── postgres.yml         ← Datasource GLPI auto-provisionnée (uid fixe)
│   │   │   └── prometheus.yml       ← Datasource Prometheus auto-provisionnée (uid fixe)
│   │   └── dashboards/
│   │       └── dashboards.yml       ← Pointeur vers les dashboards JSON
│   └── dashboards/
│       ├── glpi_dashboard.json      ← Dashboard GLPI (10 panels)
│       └── monitoring_dashboard.json ← Dashboard infra (4+ panels)
└── analyse/
    └── analyse_bdd_glpi.md          ← Analyse du schéma GLPI (Q1-Q5)
```
