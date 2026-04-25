-- =============================================================================
-- Données de démonstration GLPI — 22 tickets répartis sur 12 mois
-- Exécuté par entrypoint.sh après glpi:database:install (premier démarrage).
--
-- Statuts : 1=Nouveau 2=En cours(attribué) 3=En cours(planifié) 4=En attente
--           5=Résolu  6=Clos
-- Types   : 1=Incident  2=Demande
-- Priorité: 1=Très haute 2=Haute 3=Moyenne 4=Basse 5=Très basse
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Catégories ITIL (INSERT IGNORE : sans effet si elles existent déjà)
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO glpi_itilcategories
  (entities_id, is_recursive, name, completename, level,
   is_helpdeskvisible, is_incident, is_request, date_creation, date_mod)
VALUES
  (0, 1, 'Réseau',          'Réseau',          1, 1, 1, 1, NOW(), NOW()),
  (0, 1, 'Matériel',        'Matériel',        1, 1, 1, 1, NOW(), NOW()),
  (0, 1, 'Logiciel',        'Logiciel',        1, 1, 1, 1, NOW(), NOW()),
  (0, 1, 'Sécurité',        'Sécurité',        1, 1, 1, 1, NOW(), NOW()),
  (0, 1, 'Accès et droits', 'Accès et droits', 1, 1, 1, 1, NOW(), NOW());

-- Récupérer les IDs dans des variables pour les INSERTs suivants.
-- COALESCE(..., 0) : fallback à 0 (aucune catégorie) si le nom n'est pas trouvé.
SET @res = COALESCE((SELECT id FROM glpi_itilcategories WHERE name='Réseau'          LIMIT 1), 0);
SET @mat = COALESCE((SELECT id FROM glpi_itilcategories WHERE name='Matériel'        LIMIT 1), 0);
SET @log = COALESCE((SELECT id FROM glpi_itilcategories WHERE name='Logiciel'        LIMIT 1), 0);
SET @sec = COALESCE((SELECT id FROM glpi_itilcategories WHERE name='Sécurité'        LIMIT 1), 0);
SET @acc = COALESCE((SELECT id FROM glpi_itilcategories WHERE name='Accès et droits' LIMIT 1), 0);

-- ---------------------------------------------------------------------------
-- Tickets — colonnes essentielles uniquement.
-- Les colonnes stat (close_delay_stat, solve_delay_stat, etc.) ont toutes
-- DEFAULT 0 et ne sont pas listées ici pour simplifier les INSERTs.
-- Les champs TIMESTAMP nullable (closedate, solvedate…) restent NULL.
-- ---------------------------------------------------------------------------

-- ── Tickets récents (dans la fenêtre 30 jours du dashboard) ────────────────

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation)
VALUES (0, 'Panne réseau salle serveurs — baie 3',
  NOW() - INTERVAL 1 DAY, NOW(), NOW() - INTERVAL 1 DAY,
  2, 5, 'Switch baie 3 hors service depuis 45 min. Serveurs inaccessibles.',
  1, 1, 1, 1, 1, @res, 0, 1);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation)
VALUES (0, 'Demande accès VPN télétravail — M. Kaboré',
  NOW() - INTERVAL 2 DAY, NOW(), NOW() - INTERVAL 2 DAY,
  2, 1, 'Demande VPN pour déplacements. Service comptabilité.',
  3, 3, 3, 1, 2, @acc, 0, 1);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime)
VALUES (0, 'Office 365 refuse de s''activer — poste compta04',
  NOW() - INTERVAL 3 DAY, NOW(), NOW() - INTERVAL 3 DAY,
  2, 1, 'Erreur 0x80070005 à chaque tentative d''activation. Clé valide.',
  2, 2, 2, 2, 1, @log, 0, 1, 7200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime)
VALUES (0, 'Remplacement souris filaire — bureau 214',
  NOW() - INTERVAL 4 DAY, NOW(), NOW() - INTERVAL 4 DAY,
  2, 1, 'Souris défectueuse. Double-clic intempestif. Mme Ouédraogo.',
  4, 4, 4, 2, 2, @mat, 0, 1, 1800);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime)
VALUES (0, 'Alerte ransomware — fichiers chiffrés sur NAS01',
  NOW() - INTERVAL 5 DAY, NOW(), NOW() - INTERVAL 5 DAY,
  2, 3, 'Fichiers .encrypted sur le NAS partagé. Intervention planifiée.',
  1, 1, 1, 3, 1, @sec, 0, 1, 14400);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, waiting_duration)
VALUES (0, 'Installation Acrobat Pro — service RH (5 postes)',
  NOW() - INTERVAL 6 DAY, NOW(), NOW() - INTERVAL 6 DAY,
  2, 1, 'En attente validation licence par direction achats.',
  3, 3, 3, 4, 2, @log, 0, 1, 86400);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime, solve_delay_stat)
VALUES (0, 'WiFi instable salle de réunion B',
  NOW() - INTERVAL 8 DAY, NOW() - INTERVAL 6 DAY, NOW() - INTERVAL 8 DAY,
  2, 5, 'Déconnexions visioconférence. Résolu : canal WiFi changé.',
  2, 2, 2, 5, 1, @res, 0, 1, 10800, 172800);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime, solve_delay_stat)
VALUES (0, 'Écran noir PC-DG07 après mise à jour BIOS',
  NOW() - INTERVAL 9 DAY, NOW() - INTERVAL 7 DAY, NOW() - INTERVAL 9 DAY,
  2, 1, 'BIOS rollback effectué. Poste opérationnel.',
  2, 2, 2, 5, 1, @mat, 0, 1, 5400, 172800);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime, close_delay_stat)
VALUES (0, 'Création compte AD — stagiaire Traoré Ibrahim',
  NOW() - INTERVAL 10 DAY, NOW() - INTERVAL 8 DAY, NOW() - INTERVAL 10 DAY,
  2, 1, 'Compte créé, mail configuré, accès VPN accordé.',
  4, 4, 4, 6, 2, @acc, 0, 1, 3600, 172800);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, actiontime, close_delay_stat)
VALUES (0, 'Tentatives de connexion suspectes — compte admin GLPI',
  NOW() - INTERVAL 12 DAY, NOW() - INTERVAL 10 DAY, NOW() - INTERVAL 12 DAY,
  2, 3, 'Bruteforce détecté. MDP changé, 2FA activé, IP bloquée.',
  1, 1, 1, 6, 1, @sec, 0, 1, 7200, 172800);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation)
VALUES (0, 'Mise à jour Firefox ESR — parc complet',
  NOW() - INTERVAL 2 DAY, NOW(), NOW() - INTERVAL 2 DAY,
  2, 1, 'Déploiement Firefox ESR 128 via GPO. Aucun poste critique concerné.',
  5, 5, 5, 1, 2, @log, 0, 1);

-- ── Tickets plus anciens (fenêtre 12 mois) ──────────────────────────────────

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, solve_delay_stat)
VALUES (0, 'Imprimante HP réseau — bourrage récurrent (achats)',
  NOW() - INTERVAL 35 DAY, NOW() - INTERVAL 32 DAY, NOW() - INTERVAL 35 DAY,
  2, 1, 'Rouleau de capture changé. Imprimante opérationnelle.',
  3, 3, 3, 5, 1, @mat, 0, 1, 259200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Renouvellement certificat SSL serveur Intranet',
  NOW() - INTERVAL 38 DAY, NOW() - INTERVAL 35 DAY, NOW() - INTERVAL 38 DAY,
  2, 1, 'Certificat Let''s Encrypt renouvelé. Alerte automatique configurée.',
  2, 2, 2, 6, 2, @sec, 0, 1, 259200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, solve_delay_stat)
VALUES (0, 'VPN site-à-site Ouaga–Bobo — tunnel DOWN',
  NOW() - INTERVAL 65 DAY, NOW() - INTERVAL 62 DAY, NOW() - INTERVAL 65 DAY,
  2, 3, 'Reconfiguration IPSec Phase 2. MTU ajusté à 1400.',
  1, 2, 1, 5, 1, @res, 0, 1, 259200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Migration Exchange → Microsoft 365 (20 utilisateurs)',
  NOW() - INTERVAL 68 DAY, NOW() - INTERVAL 50 DAY, NOW() - INTERVAL 68 DAY,
  2, 1, 'Migration terminée. Données transférées. Aucune perte.',
  3, 3, 3, 6, 2, @log, 0, 1, 1555200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, solve_delay_stat)
VALUES (0, 'Serveur NAS saturation espace disque (95%)',
  NOW() - INTERVAL 95 DAY, NOW() - INTERVAL 92 DAY, NOW() - INTERVAL 95 DAY,
  2, 3, 'Nettoyage effectué. 400 Go libérés. Quota utilisateurs mis en place.',
  2, 2, 2, 5, 1, @mat, 0, 1, 259200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Déploiement GPO restrictions USB',
  NOW() - INTERVAL 98 DAY, NOW() - INTERVAL 90 DAY, NOW() - INTERVAL 98 DAY,
  2, 1, 'GPO appliquée sur 80 postes. Tests validés.',
  3, 3, 3, 6, 2, @sec, 0, 1, 691200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, solve_delay_stat)
VALUES (0, 'Routeur de bordure — CPU à 100% sous charge',
  NOW() - INTERVAL 125 DAY, NOW() - INTERVAL 122 DAY, NOW() - INTERVAL 125 DAY,
  2, 5, 'QoS reconfigurée. Trafic multicast limité. CPU stabilisé à 40%.',
  1, 2, 1, 5, 1, @res, 0, 1, 259200);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Audit accès Active Directory — rapport trimestriel',
  NOW() - INTERVAL 155 DAY, NOW() - INTERVAL 140 DAY, NOW() - INTERVAL 155 DAY,
  2, 1, '12 comptes inactifs désactivés. 3 droits excessifs retirés.',
  4, 4, 4, 6, 2, @acc, 0, 1, 1296000);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Remplacement onduleur salle serveurs (APC 3000VA)',
  NOW() - INTERVAL 185 DAY, NOW() - INTERVAL 179 DAY, NOW() - INTERVAL 185 DAY,
  2, 1, 'Onduleur remplacé. Autonomie 18 min sous charge complète.',
  2, 3, 2, 6, 2, @mat, 0, 1, 518400);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Mise en place sauvegarde Veeam — serveurs critiques',
  NOW() - INTERVAL 245 DAY, NOW() - INTERVAL 230 DAY, NOW() - INTERVAL 245 DAY,
  2, 1, 'Backup quotidien configuré. RPO 24h, RTO 4h. Test de restauration OK.',
  2, 2, 2, 6, 2, @log, 0, 1, 1296000);

INSERT INTO glpi_tickets
  (entities_id, name, date, date_mod, date_creation, users_id_recipient,
   requesttypes_id, content, urgency, impact, priority, status, type,
   itilcategories_id, is_deleted, global_validation, close_delay_stat)
VALUES (0, 'Renouvellement parc PC direction (8 postes)',
  NOW() - INTERVAL 305 DAY, NOW() - INTERVAL 285 DAY, NOW() - INTERVAL 305 DAY,
  2, 1, 'Postes livrés, configurés, données migrées. Anciens postes recyclés.',
  3, 3, 3, 6, 2, @mat, 0, 1, 1728000);
