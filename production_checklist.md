# Liste de contrôle de mise en production

## Décision actuelle : backend GO, distribution mobile NO-GO

Cette liste est un registre de preuves, pas une estimation commerciale. Une case n'est cochée que lorsqu'une preuve reproductible existe pour la version candidate. Le backend Wix/Stripe est actif et validé, mais l'application ne doit pas être présentée comme prête pour les stores avant la fermeture de tous les éléments mobiles marqués **bloquant**. Les preuves datées sont consignées dans [`PRODUCTION_EVIDENCE_2026-09-22.md`](PRODUCTION_EVIDENCE_2026-09-22.md).

## État confirmé dans le dépôt

- [x] Identifiant Android : `ca.indexcanada.app`.
- [x] Bundle Identifier iOS : `ca.indexcanada.app`.
- [x] Nom affiché Android/iOS : `Index Canada`.
- [x] Version candidate actuelle du projet : `1.1.0+25` (supérieure à iOS `1.0.4 (24)` et Android `1.0.3 (21)`).
- [x] Minification et réduction des ressources activées pour Android release.
- [x] Le build Android release exige une signature, sauf dérogation CI explicite produisant un artefact non distribuable.
- [x] La CI iOS compile sans signature et ne produit pas d'archive soumissible.
- [x] Firebase Analytics est désactivé par un stub ; aucun événement Firebase n'est actuellement collecté.
- [x] Permissions Android déclarées : réseau et caméra seulement. Aucune permission de localisation, d'appel téléphonique ou de stockage.
- [x] Des contrôles automatisés existent pour l'analyse, les tests et les compilations.
- [x] Passage complet réussi archivé sur le commit exact `19f9fdf` : [Flutter CI #6](https://github.com/farouk60/index-canada-app/actions/runs/35740889950), trois tâches vertes.
- [ ] **Bloquant —** Exécuter et consigner de vrais tests de bout en bout avec Wix, Stripe et des appareils Android/iOS.

## 1. Backend Wix — bloquant

- [ ] Exécuter intégralement le guide [`WIX_DEPLOYMENT.md`](WIX_DEPLOYMENT.md) dans l'environnement de préproduction, puis en production.
- [x] Installer `stripe@22.6.2` dans le Package Manager Wix, vérifier qu'il correspond exactement à `backend/package-lock.json` et prouver son chargement en préproduction.
- [ ] Confirmer les schémas, index et permissions des collections utilisées, notamment les professionnels, catégories, avis, partenaires, offres, `PaymentCheckouts` et `ApiRateLimits`.
- [ ] Interdire les écritures directes publiques sur les collections sensibles ; faire passer les mutations par les fonctions backend validées.
- [x] Vérifier que seules les colonnes nécessaires sont retournées au client.
- [ ] Tester la pagination sur plusieurs pages pour chaque collection et confirmer qu'aucune donnée n'est silencieusement tronquée.
- [ ] Tester les limites maximales de jeux de données et le message d'échec opérationnel associé.
- [ ] Tester les routes v2 `/categories`, `/professionals`, `/reviews`, `/partners` et `/offers` sur plusieurs pages, avec `limit`, `cursor` et tous leurs filtres; confirmer que `/data` reste seulement une compatibilité v1 mesurée.
- [ ] Vérifier les index Wix utilisés pour les états actifs/approuvés/officiels, `sponsor`, la catégorie, `professionalId` et l'ordre `_id`, y compris les anciens champs encore présents pendant la migration.
- [ ] Tester qu'un curseur malformé/non canonique ou réutilisé avec d'autres filtres est rejeté, que le client détecte un curseur répété et qu'une page d'éléments masqués progresse sans boucle ni doublon.
- [ ] Confirmer que les images validées sont envoyées à Wix Media Manager et que les collections ne contiennent ni Base64 ni binaire volumineux.
- [ ] Tester le nettoyage des médias en cas d'échec ou de concurrence entre deux inscriptions.
- [x] Configurer les secrets de production dans Wix Secrets Manager et vérifier qu'aucun secret n'est exposé dans l'arbre courant ou les réponses publiques validées.
- [x] Révoquer et remplacer les anciennes clés Wix ou Stripe connues; les valeurs historiques sont désormais inactives.
- [ ] Vérifier les règles CORS, les limites de débit et les réponses d'erreur génériques depuis un domaine/appareil non autorisé.
- [x] Vérifier qu'une finalisation financière n'active ni ne publie automatiquement un profil; l'approbation humaine Wix reste obligatoire.
- [ ] Activer des journaux exploitables sans données personnelles, secrets ni contenu d'images.

## 2. Stripe — bloquant

- [x] Vérifier le catalogue de forfaits, les montants et la devise directement dans l'environnement de production.
- [x] Configurer le webhook de production et son secret dans Wix; la destination finale n'écoute que `payment_intent.succeeded`.
- [x] Valider la signature du webhook et rejeter les événements invalides.
- [ ] Tester un forfait gratuit sans création de PaymentIntent.
- [ ] Tester un paiement réussi sur l'application native avec une clé de test et le webhook actif.
- [x] Vérifier qu'un paiement réussi confirme le volet financier sans activer ni publier automatiquement le profil.
- [ ] Tester paiement refusé, annulation, 3-D Secure et interruption réseau.
- [x] Renvoyer plusieurs fois le même webhook et la même confirmation ; vérifier l'absence de double débit et de profil dupliqué.
- [ ] Vérifier qu'un identifiant Stripe appartenant à un autre forfait ou professionnel est refusé.
- [ ] Rapprocher dans Stripe, Wix et l'application le montant, le statut, le profil et les identifiants d'idempotence.
- [ ] Confirmer dans les fiches store que le paiement payant Web n'est pas annoncé comme disponible.

## 3. Confidentialité et aspects juridiques — bloquant

- [ ] Publier une politique de confidentialité spécifique à Index Canada sur une URL publique stable.
- [ ] Ajouter un accès à cette politique dans l'application.
- [ ] Inventorier les données réellement envoyées à Wix et Stripe : coordonnées professionnelles, adresse, photos, identifiants techniques et données liées au paiement.
- [ ] Vérifier la finalité, la durée de conservation, l'accès interne et la procédure de suppression de chaque type de donnée.
- [ ] Compléter Google Play « Sécurité des données » à partir de l'inventaire observé, pas à partir d'hypothèses.
- [ ] Compléter App Store « App Privacy » avec les mêmes pratiques réelles.
- [ ] Vérifier si l'inscription professionnelle déclenche les exigences de suppression de compte et, si applicable, fournir le parcours dans l'application et le lien Web requis.
- [ ] Faire approuver les conditions d'utilisation, la politique de confidentialité et les déclarations store.
- [ ] Ne pas déclarer Firebase Analytics ou Crashlytics comme actifs tant qu'ils restent absents/désactivés.

## 4. QA de la version candidate — bloquant

- [x] Geler le commit `19f9fdf` et consigner la version `1.0.3+21`, la configuration et l'environnement testés.
- [x] Analyse statique, suites automatisées et compilations non signées réussies sur ce commit dans la CI.
- [ ] Android réel : installation depuis Google Play test interne, démarrage et parcours critiques réussis.
- [ ] iPhone réel : installation depuis TestFlight, démarrage et parcours critiques réussis.
- [ ] Vérifier FR et EN, changement de langue, petite largeur et grande taille de texte.
- [ ] Vérifier recherche, catégories, fiches, partenaires, offres, favoris et liens externes.
- [ ] Vérifier inscription gratuite et payante, téléversement caméra/galerie et reprise après erreur.
- [ ] Tester accord, refus et refus permanent des permissions caméra/photos.
- [ ] Tester hors ligne, réseau lent, expiration, réponses Wix invalides et reprise.
- [ ] Vérifier qu'aucune donnée personnelle ni aucun secret n'apparaît dans les journaux.
- [ ] Aucun défaut critique ou majeur ouvert ; les risques résiduels sont acceptés par la personne responsable du produit.

## 5. Android / Google Play — bloquant

- [ ] Compte développeur et profil Play Console vérifiés.
- [ ] Application créée avec le package immuable `ca.indexcanada.app`.
- [ ] Play App Signing activé et clé d'envoi sauvegardée de façon sécurisée.
- [ ] `android/key.properties` local configuré sans être versionné.
- [ ] AAB de production compilé avec les vraies valeurs approuvées et une signature vérifiée.
- [ ] Démarrage de l'AAB confirmé avec `APP_ENVIRONMENT=production`, une `API_BASE_URL` HTTPS non factice et une clé Stripe publique `pk_live_` du compte attendu.
- [ ] Version installée et testée depuis le canal interne Google Play.
- [ ] Exigences de test fermé du compte vérifiées et satisfaites, si applicables.
- [ ] Politique de confidentialité, sécurité des données, accès à l'application, public cible, classification du contenu et déclarations requises complétés.
- [ ] Icône, bannière et captures conformes et représentatives de la version testée.
- [ ] Description FR et EN relue ; aucune promesse de qualification, de couverture nationale ou de fonctionnalité non démontrée.
- [ ] Déploiement progressif et procédure de retour arrière approuvés.

## 6. iOS / App Store — bloquant

- [ ] Adhésion Apple Developer et contrats App Store Connect actifs.
- [ ] App ID `ca.indexcanada.app`, équipe, certificats et profils de provisionnement configurés.
- [ ] Archive Release signée avec les vraies valeurs de production.
- [ ] Démarrage de l'archive confirmé avec `APP_ENVIRONMENT=production`, une `API_BASE_URL` HTTPS non factice et une clé Stripe publique `pk_live_` du compte attendu.
- [ ] Version installée et testée depuis TestFlight.
- [ ] `Info.plist` et `PrivacyInfo.xcprivacy` validés contre les SDK et comportements réels.
- [ ] Fiche App Privacy, public cible, classification et informations de révision complétées.
- [ ] Captures et métadonnées FR/EN représentatives de la version testée.
- [ ] Soumission App Store approuvée par la personne responsable du produit.

## 7. Exploitation et lancement — bloquant

- [ ] Responsables nommés pour Wix, Stripe, stores, confidentialité et support utilisateur.
- [ ] Alertes et procédure d'investigation définies pour les échecs de webhook, d'inscription et d'envoi de média.
- [ ] Android vitals et métriques App Store surveillés dès la bêta.
- [ ] Canal support, délai de réponse et procédure d'incident publiés.
- [ ] Procédure de désactivation d'un forfait ou du paiement testée.
- [ ] Sauvegarde/export des données Wix et procédure de restauration vérifiés.
- [ ] Décision GO datée et signée après revue de toutes les preuves.

## 8. Indicateurs produit après lancement

Aucun volume de téléchargements, revenu, taux de pénétration ou retour sur investissement n'est confirmé par le dépôt. Les objectifs doivent être établis avec une source, une période et un responsable après mesure d'une bêta.

| Indicateur | Référence de départ | Objectif approuvé | Période | Responsable |
| --- | --- | --- | --- | --- |
| Installations actives | À mesurer | À définir | À définir | À définir |
| Recherche vers ouverture de fiche | À mesurer | À définir | À définir | À définir |
| Inscription commencée vers complétée | À mesurer | À définir | À définir | À définir |
| Paiements réussis / tentatives | À mesurer | À définir | À définir | À définir |
| Rétention et désinstallation | À mesurer | À définir | À définir | À définir |
| Demandes support et incidents | À mesurer | À définir | À définir | À définir |

Le suivi ne doit être activé qu'après choix d'un mécanisme conforme à la politique de confidentialité. Firebase Analytics et Crashlytics ne sont pas actifs dans l'état actuel.
