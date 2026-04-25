# Analyse de la base de données GLPI

## Connexion à la base MariaDB

```bash
# Se connecter au shell MariaDB dans le conteneur
docker compose exec mariadb mysql -u glpi_user -p glpi
# Saisir le mot de passe MARIADB_PASSWORD depuis .env
```

---

## Q1 — Les 10 tables principales de GLPI

### Requête de listing

```sql
-- Lister les tables GLPI avec leur taille approximative
-- MySQL/MariaDB : information_schema.tables pour les métadonnées
SELECT
  table_name,
  ROUND((data_length + index_length) / 1024, 0) AS taille_ko,
  table_rows AS lignes_approx
FROM information_schema.tables
WHERE table_schema = DATABASE()  -- la base courante (glpi)
  AND table_type = 'BASE TABLE'
ORDER BY (data_length + index_length) DESC
LIMIT 20;
```

### Description des 10 tables clés

| Table | Rôle |
|-------|------|
| `glpi_tickets` | Table centrale de l'ITSM. Stocke tous les tickets (incidents, demandes de service). Chaque ligne représente un ticket avec son statut, priorité, date de création (colonne DATETIME/TIMESTAMP native), entité, catégorie et type. |
| `glpi_computers` | Inventaire des ordinateurs (fixes et portables). Contient le nom, le numéro de série, le modèle, le système d'exploitation et l'utilisateur associé. |
| `glpi_users` | Annuaire des utilisateurs GLPI (techniciens, utilisateurs finaux, administrateurs). Contient les informations de profil, les droits et les entités accessibles. |
| `glpi_entities` | Structure organisationnelle hiérarchique (entreprises, sites, départements). Tous les objets GLPI appartiennent à une entité. |
| `glpi_itilcategories` | Catégories ITIL utilisées pour classifier les tickets (ex : Réseau, Matériel, Logiciel). Supporte une hiérarchie via `completename`. |
| `glpi_ticketusers` | Table de liaison entre tickets et utilisateurs. Distingue les rôles : demandeur (type=1), observateur (type=3), technicien assigné (type=2). |
| `glpi_networkequipments` | Équipements réseau (switches, routeurs, pare-feu). Intégré à l'inventaire matériel de GLPI. |
| `glpi_software` | Logiciels enregistrés dans l'inventaire. Liés aux ordinateurs via `glpi_items_softwareversions`. |
| `glpi_slms` | Service Level Management — définit les SLA (délais de prise en charge, de résolution). Référencé dans les tickets via `slas_id_ttr` et `slas_id_tto`. |
| `glpi_groups` | Groupes d'utilisateurs (équipes support, services). Utilisés pour l'assignation collective des tickets. |

---

## Q2 — Nombre de tickets par statut

```sql
-- Comptage des tickets actifs par statut avec libellés explicites
-- Référence des statuts GLPI :
--   1 = Nouveau         → ticket créé, non encore pris en charge
--   2 = En cours (attribué)   → assigné à un technicien
--   3 = En cours (planifié)   → intervention planifiée à une date précise
--   4 = En attente      → bloqué en attente d'information ou d'action externe
--   5 = Résolu          → solution apportée, en attente de validation
--   6 = Clos            → ticket fermé définitivement

SELECT
  CASE status
    WHEN 1 THEN 'Nouveau'
    WHEN 2 THEN 'En cours (attribue)'
    WHEN 3 THEN 'En cours (planifie)'
    WHEN 4 THEN 'En attente'
    WHEN 5 THEN 'Resolu'
    WHEN 6 THEN 'Clos'
    ELSE CONCAT('Statut inconnu (', status, ')')
  END AS statut,
  COUNT(*) AS nombre,
  -- Pourcentage par rapport au total (window function, MariaDB 10.2+)
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pourcentage
FROM glpi_tickets
WHERE is_deleted = 0  -- exclure les tickets supprimés (corbeille)
GROUP BY status
ORDER BY status;
```

**Signification des statuts GLPI :**
- **1 — Nouveau** : Ticket créé, non encore attribué à un technicien
- **2 — En cours (attribué)** : Un technicien est assigné, le travail est en cours
- **3 — En cours (planifié)** : Une intervention est planifiée à une date donnée
- **4 — En attente** : Ticket bloqué (attente pièce, attente réponse utilisateur…)
- **5 — Résolu** : Solution fournie, le ticket attend la validation de l'utilisateur
- **6 — Clos** : Ticket définitivement fermé après validation

---

## Q3 — Tickets créés par mois sur 12 mois

```sql
-- Évolution mensuelle des créations de tickets sur les 12 derniers mois glissants
-- NOTE : date_creation dans GLPI 10.x est un type DATETIME/TIMESTAMP natif,
-- pas un entier Unix — on utilise directement DATE_FORMAT() sans FROM_UNIXTIME()

SELECT
  DATE_FORMAT(date_creation, '%Y-%m') AS mois,
  COUNT(*) AS tickets_crees,
  -- Cumul glissant pour visualiser la tendance (window function MariaDB 10.2+)
  SUM(COUNT(*)) OVER (
    ORDER BY DATE_FORMAT(date_creation, '%Y-%m')
  ) AS cumul
FROM glpi_tickets
WHERE
  -- Filtre sur les 12 derniers mois (comparaison directe DATETIME)
  date_creation >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
  AND is_deleted = 0
GROUP BY DATE_FORMAT(date_creation, '%Y-%m')
ORDER BY mois;
```

---

## Q4 — Équipements associés à un utilisateur

> **Données de démo disponibles** : 8 ordinateurs et 4 périphériques sont pré-insérés par
> `seed_tickets.sql`. Remplacer `'nom_utilisateur'` par `'normal'` pour obtenir 4 postes,
> `'tech'` pour 2 postes, `'glpi'` pour 1 poste.

```sql
-- Retrouver tous les ordinateurs et périphériques associés à un utilisateur donné
-- La relation se fait via glpi_computers.users_id (utilisateur principal)
-- ou via glpi_items_users pour les associations multiples

-- Méthode 1 : via le champ users_id direct (utilisateur principal)
SELECT
  u.name          AS login_utilisateur,
  u.firstname     AS prenom,
  u.realname      AS nom,
  c.name          AS ordinateur,
  c.serial        AS numero_serie,
  c.otherserial   AS inventaire,
  os.name         AS systeme_exploitation,
  e.completename  AS entite
FROM glpi_users u
JOIN glpi_computers c ON c.users_id = u.id
LEFT JOIN glpi_operatingsystems os ON os.id = c.operatingsystems_id
LEFT JOIN glpi_entities e ON e.id = c.entities_id
WHERE
  u.name = 'normal'  -- utilisateur de démo ; remplacer par le login recherché
  AND c.is_deleted = 0
ORDER BY c.name;

-- Méthode 2 : via la table de liaison glpi_items_users (associations multiples)
SELECT
  u.name                              AS login,
  CONCAT(u.firstname, ' ', u.realname) AS nom_complet,
  gi.itemtype                          AS type_equipement,
  -- Résolution dynamique du nom selon le type d'item
  CASE gi.itemtype
    WHEN 'Computer'   THEN (SELECT name FROM glpi_computers WHERE id = gi.items_id)
    WHEN 'Peripheral' THEN (SELECT name FROM glpi_peripherals WHERE id = gi.items_id)
    WHEN 'Phone'      THEN (SELECT name FROM glpi_phones WHERE id = gi.items_id)
    WHEN 'Printer'    THEN (SELECT name FROM glpi_printers WHERE id = gi.items_id)
  END AS nom_equipement,
  gi.type         AS type_association  -- 1=Utilisateur principal, 4=Contact
FROM glpi_users u
JOIN glpi_items_users gi ON gi.users_id = u.id
WHERE u.name = 'nom_utilisateur'
ORDER BY gi.itemtype, nom_equipement;
```

---

## Q5 — Tables SLA et relation avec glpi_tickets

### Tables et champs SLA

```sql
-- Explorer la structure de la table glpi_slms
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'glpi_slms'
ORDER BY ordinal_position;

-- Explorer les niveaux SLA (escalades)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'glpi_slalevels'
ORDER BY ordinal_position;
```

### Architecture SLA dans GLPI

```
glpi_slms          → Définit les contrats SLA (nom, type TTO/TTR, calendrier)
  └── glpi_slalevels    → Niveaux d'escalade avec délais en secondes
        └── glpi_slalevelactions  → Actions automatiques en cas de dépassement

glpi_tickets       → Référence les SLA via :
  ├── slas_id_tto  → SLA Time To Own   (délai de prise en charge)
  └── slas_id_ttr  → SLA Time To Resolve (délai de résolution)
```

### Requête d'analyse des SLA

```sql
-- Analyse du respect des SLA pour les tickets résolus
-- time_to_own et time_to_resolve sont des colonnes DATETIME (échéances absolues)
-- takeintoaccount_delay_stat et close_delay_stat sont des entiers en secondes
-- Comparaison SLA : solvedate (DATETIME réelle) vs time_to_resolve (DATETIME cible)

SELECT
  t.id                                    AS ticket_id,
  t.name                                  AS titre,
  slm_tto.name                            AS sla_prise_en_charge,
  slm_ttr.name                            AS sla_resolution,
  -- Délai réel de prise en charge converti en heures
  ROUND(t.takeintoaccount_delay_stat / 3600.0, 2)  AS delai_pec_heures,
  -- Délai réel de résolution en heures
  ROUND(t.close_delay_stat / 3600.0, 2)            AS duree_resolution_heures,
  -- Date de création lisible (DATETIME natif → DATE_FORMAT direct)
  DATE_FORMAT(t.date_creation, '%d/%m/%Y %H:%i')   AS date_creation,
  -- Indicateur de respect du SLA TTR (date résolution réelle vs échéance SLA)
  CASE
    WHEN t.time_to_resolve IS NULL THEN 'Pas de SLA TTR'
    WHEN t.solvedate IS NULL        THEN 'Non résolu'
    WHEN t.solvedate <= t.time_to_resolve THEN 'SLA respecte'
    ELSE 'SLA depasse'
  END AS statut_sla
FROM glpi_tickets t
LEFT JOIN glpi_slms slm_tto ON slm_tto.id = t.slas_id_tto
LEFT JOIN glpi_slms slm_ttr ON slm_ttr.id = t.slas_id_ttr
WHERE t.is_deleted = 0
  AND t.status IN (5, 6)  -- tickets résolus ou clos
ORDER BY t.date_creation DESC
LIMIT 20;
```

### Explication de la relation glpi_tickets ↔ glpi_slms

| Champ dans `glpi_tickets` | Référence | Description |
|---|---|---|
| `slas_id_tto` | `glpi_slms.id` | SLA définissant le délai maximal de prise en charge (Time To Own) |
| `slas_id_ttr` | `glpi_slms.id` | SLA définissant le délai maximal de résolution (Time To Resolve) |
| `time_to_own` | — | Échéance TTO calculée (DATETIME) — deadline de prise en charge |
| `time_to_resolve` | — | Échéance TTR calculée (DATETIME) — deadline de résolution |
| `takeintoaccount_delay_stat` | — | Délai réel de prise en charge en secondes |
| `close_delay_stat` | — | Délai réel de résolution en secondes |

**Interprétation** : un SLA TTR est respecté si `solvedate <= time_to_resolve` (deux colonnes DATETIME). GLPI calcule automatiquement `time_to_resolve` à partir de la date de création et du calendrier de travail défini dans `glpi_slms.calendars_id`, ce qui exclut nuits et week-ends du calcul du délai.
