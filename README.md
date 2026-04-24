# TP Intégration Logicielle — Stack GLPI + Grafana + Prometheus

**Module :** Intégration Logicielle — M2 ISIE IBAM  
**Enseignant :** Charles BATIONO  
**Auteurs :** [Prénom NOM] — [Prénom NOM] *(compléter avec les noms du groupe)*

---

## Présentation du projet

Ce projet déploie une infrastructure d'entreprise complète en **une seule commande** :

```
docker compose up -d
```

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

> **Premier démarrage** : GLPI prend **1 à 2 minutes** pour initialiser sa base de données. Suivre les logs :
> ```bash
> docker compose logs -f glpi
> ```
> Attendre le message indiquant que la base est initialisée avant d'accéder à l'interface.

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

### 1. Timestamps Unix dans GLPI
**Problème :** Grafana ne reconnaît pas automatiquement les colonnes `date_creation` de GLPI car elles sont stockées comme des entiers Unix et non comme des types `TIMESTAMP` natifs PostgreSQL.  
**Solution :** Utiliser `to_timestamp(date_creation)` dans toutes les requêtes SQL et configurer le format `time_series` avec `timeColumn: "time"` dans les panels Grafana.

### 2. cAdvisor sur Windows (WSL2)
**Problème :** Les chemins `/var/lib/docker` et `/sys` n'existent pas directement sur Windows. cAdvisor doit accéder au système de fichiers de l'hôte WSL2.  
**Solution :** Activer WSL2 comme backend Docker Desktop et lancer la stack depuis un terminal WSL2. Le flag `privileged: true` est également nécessaire pour l'accès aux cgroups.

### 3. Ordre de démarrage des services
**Problème :** GLPI tentait de se connecter à PostgreSQL avant que celui-ci soit prêt, causant des erreurs de connexion au premier démarrage.  
**Solution :** Implémenter un `healthcheck` sur le service `postgres` et utiliser `condition: service_healthy` dans la dépendance GLPI, ce qui force Docker Compose à attendre que PostgreSQL accepte réellement des connexions.

### 4. Variables d'environnement dans les fichiers de provisioning Grafana
**Problème :** Les variables `${POSTGRES_PASSWORD}` dans `postgres.yml` n'étaient pas résolues automatiquement par Grafana.  
**Solution :** Passer les variables via les variables d'environnement du conteneur Grafana dans `docker-compose.yml` (`environment:`) et s'assurer que le fichier `.env` est bien lu par Docker Compose.

### 5. Résolution DNS entre conteneurs
**Problème :** Grafana ne pouvait pas résoudre `postgres` comme hostname.  
**Solution :** S'assurer que tous les services sont sur le même réseau Docker dédié (`glpi_network`). Docker Compose crée automatiquement une entrée DNS pour chaque service, mais uniquement pour les services partageant le même réseau.

---

## Structure du projet

```
tp-integration/
├── docker-compose.yml          ← Orchestration de toute la stack
├── .env                        ← Variables sensibles (non versionné)
├── .env.example                ← Template à copier
├── .gitignore
├── README.md                   ← Ce fichier
├── prometheus/
│   └── prometheus.yml          ← Configuration scrape Prometheus
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   ├── postgres.yml    ← Datasource GLPI auto-provisionnée
│   │   │   └── prometheus.yml  ← Datasource Prometheus auto-provisionnée
│   │   └── dashboards/
│   │       └── dashboards.yml  ← Pointeur vers les dashboards JSON
│   └── dashboards/
│       ├── glpi_dashboard.json      ← Dashboard GLPI (6+ panels)
│       └── monitoring_dashboard.json ← Dashboard infra (4 panels)
└── analyse/
    └── analyse_bdd_glpi.md     ← Analyse du schéma GLPI (Q1-Q5)
```
