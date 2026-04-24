# Analyse de la base de données GLPI

## Connexion à la base

```bash
docker compose exec postgres psql -U glpi_user -d glpi
```

---

## Q1 — Les 10 tables principales de GLPI

### Requête de listing

```sql
-- Lister toutes les tables du schéma public avec leur nombre approximatif de lignes
SELECT
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS taille
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

### Description des 10 tables clés

| Table | Rôle |
|-------|------|
| `glpi_tickets` | Table centrale de l'ITSM. Stocke tous les tickets (incidents, demandes de service). Chaque ligne représente un ticket avec son statut, priorité, date de création (timestamp Unix), entité, catégorie et type. |
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
    WHEN 2 THEN 'En cours (attribué)'
    WHEN 3 THEN 'En cours (planifié)'
    WHEN 4 THEN 'En attente'
    WHEN 5 THEN 'Résolu'
    WHEN 6 THEN 'Clos'
    ELSE 'Statut inconnu (' || status::text || ')'
  END AS statut,
  COUNT(*) AS nombre,
  -- Pourcentage par rapport au total
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
-- NOTE : date_creation dans GLPI est un entier Unix (secondes depuis epoch)
-- to_timestamp() le convertit en type TIMESTAMP pour DATE_TRUNC

SELECT
  to_char(
    DATE_TRUNC('month', to_timestamp(date_creation)),
    'YYYY-MM'
  ) AS mois,
  COUNT(*) AS tickets_créés,
  -- Cumul glissant pour visualiser la tendance
  SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', to_timestamp(date_creation))) AS cumul
FROM glpi_tickets
WHERE
  -- Filtre sur les 12 derniers mois (conversion INTERVAL → epoch)
  date_creation >= EXTRACT(EPOCH FROM NOW() - INTERVAL '12 months')
  AND is_deleted = 0
GROUP BY DATE_TRUNC('month', to_timestamp(date_creation))
ORDER BY mois;
```

---

## Q4 — Équipements associés à un utilisateur

```sql
-- Retrouver tous les ordinateurs et périphériques associés à un utilisateur donné
-- La relation se fait via glpi_computers.users_id (utilisateur principal)
-- ou via glpi_items_users pour les associations multiples

-- Méthode 1 : via le champ users_id direct (utilisateur principal)
SELECT
  u.name          AS login_utilisateur,
  u.firstname     AS prénom,
  u.realname      AS nom,
  c.name          AS ordinateur,
  c.serial        AS numéro_série,
  c.otherserial   AS inventaire,
  os.name         AS système_exploitation,
  e.completename  AS entité
FROM glpi_users u
JOIN glpi_computers c ON c.users_id = u.id
LEFT JOIN glpi_operatingsystems os ON os.id = c.operatingsystems_id
LEFT JOIN glpi_entities e ON e.id = c.entities_id
WHERE
  u.name = 'nom_utilisateur'  -- remplacer par le login recherché
  AND c.is_deleted = 0
ORDER BY c.name;

-- Méthode 2 : via la table de liaison glpi_items_users (associations multiples)
SELECT
  u.name          AS login,
  u.firstname || ' ' || u.realname AS nom_complet,
  gi.itemtype     AS type_équipement,
  -- Résolution dynamique du nom selon le type d'item
  CASE gi.itemtype
    WHEN 'Computer'   THEN (SELECT name FROM glpi_computers WHERE id = gi.items_id)
    WHEN 'Peripheral' THEN (SELECT name FROM glpi_peripherals WHERE id = gi.items_id)
    WHEN 'Phone'      THEN (SELECT name FROM glpi_phones WHERE id = gi.items_id)
    WHEN 'Printer'    THEN (SELECT name FROM glpi_printers WHERE id = gi.items_id)
  END AS nom_équipement,
  gi.type         AS type_association  -- 1=Utilisateur principal, 4=Contact
FROM glpi_users u
JOIN glpi_items_users gi ON gi.users_id = u.id
WHERE u.name = 'nom_utilisateur'
ORDER BY gi.itemtype, nom_équipement;
```

---

## Q5 — Tables SLA et relation avec glpi_tickets

### Tables et champs SLA

```sql
-- Explorer la structure de la table glpi_slms
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_name = 'glpi_slms'
ORDER BY ordinal_position;

-- Explorer les niveaux SLA (escalades)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'glpi_slalevels'
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
-- time_to_own et time_to_resolve sont en secondes dans GLPI

SELECT
  t.id                            AS ticket_id,
  t.name                          AS titre,
  slm_tto.name                    AS sla_prise_en_charge,
  slm_ttr.name                    AS sla_résolution,
  -- Délai de prise en charge réel vs SLA
  t.time_to_own                   AS délai_prise_en_charge_sla_s,
  CASE
    WHEN t.time_to_own IS NOT NULL AND t.time_to_own > 0
    THEN ROUND(t.time_to_own / 3600.0, 2)
    ELSE NULL
  END AS délai_tto_heures,
  -- Délai de résolution réel
  t.close_delay_stat              AS durée_résolution_s,
  -- Indicateur de respect du SLA
  CASE
    WHEN t.takeintoaccount_delay_stat <= t.time_to_own
      OR t.time_to_own IS NULL THEN 'SLA respecté'
    ELSE 'SLA dépassé'
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
| `time_to_own` | — | Timestamp Unix de l'échéance TTO calculée |
| `time_to_resolve` | — | Timestamp Unix de l'échéance TTR calculée |
| `takeintoaccount_delay_stat` | — | Délai réel de prise en charge en secondes |
| `close_delay_stat` | — | Délai réel de résolution en secondes |

**Interprétation** : un SLA est respecté si `takeintoaccount_delay_stat <= (time_to_own - date_creation)`. GLPI calcule automatiquement ces valeurs en tenant compte du calendrier de travail défini dans `glpi_slms.calendars_id`.
