# Liste de contrôle de mise en production

## Décision actuelle : migration abonnement en cours, distribution mobile NO-GO

Cette liste est un registre de preuves, pas une estimation commerciale. Une case n'est cochée que lorsqu'une preuve reproductible existe pour la version candidate. Le backend Wix/Stripe Web existant ne prouve pas la nouvelle chaîne StoreKit/Google Play Billing. L'application ne doit pas être présentée comme prête avant la fermeture de tous les éléments marqués **bloquant**.

## État confirmé dans le dépôt

- [x] Identifiant Android : `ca.indexcanada.app`.
- [x] Bundle Identifier iOS : `ca.indexcanada.app`.
- [x] Nom affiché Android/iOS : `Index Canada`.
- [ ] Version candidate cible : `1.1.0+27`; le build TestFlight `1.1.0 (25)` contient encore Stripe natif et ne doit pas être soumis.
- [x] Minification et réduction des ressources activées pour Android release.
- [x] Le build Android release exige une signature, sauf dérogation CI explicite produisant un artefact non distribuable.
- [x] La CI iOS compile sans signature et ne produit pas d'archive soumissible.
- [x] Firebase Analytics est désactivé par un stub ; aucun événement Firebase n'est actuellement collecté.
- [x] Permissions Android déclarées : réseau et caméra seulement. Aucune permission de localisation, d'appel téléphonique ou de stockage.
- [x] Des contrôles automatisés existent pour l'analyse, les tests et les compilations.
- [x] Passage complet réussi archivé sur le commit exact `19f9fdf` : [Flutter CI #6](https://github.com/farouk60/index-canada-app/actions/runs/35740889950), trois tâches vertes.
- [ ] **Bloquant —** Exécuter et consigner les achats, restaurations et révocations StoreKit/Google Play Billing de bout en bout avec Wix sur de vrais appareils.

## 1. Backend Wix — bloquant

- [ ] Exécuter intégralement le guide [`WIX_DEPLOYMENT.md`](WIX_DEPLOYMENT.md) dans l'environnement de préproduction, puis en production.
- [ ] Installer dans Wix les versions exactes verrouillées par `backend/package-lock.json` et prouver leur chargement en préproduction.
- [ ] Confirmer les schémas, index et permissions des collections utilisées, notamment les professionnels, catégories, avis, partenaires, offres, `PaymentCheckouts`, `Entitlements`, `PaymentEvents` et `ApiRateLimits`.
- [ ] Interdire les écritures directes publiques sur les collections sensibles ; faire passer les mutations par les fonctions backend validées.
- [x] Vérifier que seules les colonnes nécessaires sont retournées au client.
- [ ] Tester la pagination sur plusieurs pages pour chaque collection et confirmer qu'aucune donnée n'est silencieusement tronquée.
- [ ] Tester les limites maximales de jeux de données et le message d'échec opérationnel associé.
- [ ] Tester les routes v2 `/categories`, `/professionals`, `/reviews`, `/partners` et `/offers` sur plusieurs pages, avec `limit`, `cursor` et tous leurs filtres; confirmer que `/data` reste seulement une compatibilité v1 mesurée.
- [ ] Vérifier les index Wix utilisés pour les états actifs/approuvés/officiels, `sponsor`, la catégorie, `professionalId` et l'ordre `_id`, y compris les anciens champs encore présents pendant la migration.
- [ ] Tester qu'un curseur malformé/non canonique ou réutilisé avec d'autres filtres est rejeté, que le client détecte un curseur répété et qu'une page d'éléments masqués progresse sans boucle ni doublon.
- [ ] Confirmer que les images validées sont envoyées à Wix Media Manager et que les collections ne contiennent ni Base64 ni binaire volumineux.
- [ ] Tester le nettoyage des médias en cas d'échec ou de concurrence entre deux inscriptions.
- [ ] Ajouter une purge bornée des checkouts expirés et de leurs médias devenus orphelins, puis vérifier qu'elle n'efface jamais un média référencé.
- [ ] **Bloquant —** Configurer les nouveaux secrets Apple/Google de Store Billing dans Wix Secrets Manager; aucun secret n'est exposé dans l'arbre courant ou les réponses publiques validées.
- [x] Révoquer et remplacer les anciennes clés Wix ou Stripe connues; les valeurs historiques sont désormais inactives.
- [ ] Vérifier les règles CORS, les limites de débit et les réponses d'erreur génériques depuis un domaine/appareil non autorisé.
- [x] Vérifier qu'une finalisation financière n'active ni ne publie automatiquement un profil; l'approbation humaine Wix reste obligatoire.
- [ ] Activer des journaux exploitables sans données personnelles, secrets ni contenu d'images.

## 2. Abonnements Apple et Google — bloquant

- [ ] Créer `ca.indexcanada.app.premium.annual` et `ca.indexcanada.app.professional.annual` dans App Store Connect et Google Play avec une période annuelle.
- [ ] Vérifier les prix et localisations FR/EN directement dans chaque console.
- [ ] Tester le forfait gratuit sans démarrer d'achat store.
- [ ] Valider côté serveur un achat sandbox Apple et un achat test Google; refuser toute assertion non vérifiée du client.
- [ ] Tester achat réussi, en attente, refus, annulation, restauration, renouvellement, expiration, remboursement/révocation et interruption réseau.
- [ ] Vérifier qu'un abonnement actif confirme seulement le droit commercial sans activer ni publier automatiquement le profil.
- [ ] Rejouer la même transaction et la même notification; confirmer l'absence de double droit, double profil ou double événement.
- [ ] Vérifier qu'un produit, jeton, compte ou application ne correspondant pas au checkout est refusé.
- [ ] Configurer et tester App Store Server Notifications V2 et Google Real-time Developer Notifications.
- [ ] **Bloquant résilience —** Ajouter et valider une réconciliation quotidienne Apple/Google pour corriger un droit lorsque toutes les notifications temps réel ont été manquées.
- [ ] **Bloquant confirmé —** Play Console affiche actuellement les notifications en temps réel désactivées et aucun sujet Cloud Pub/Sub; créer le sujet, accorder la publication Google, enregistrer son nom puis envoyer une notification test.
- [ ] Confirmer l'absence de PaymentSheet, schéma `flutterstripe` et clé Stripe dans les binaires mobiles; Stripe reste Web/legacy seulement.

## 3. Confidentialité et aspects juridiques — bloquant

- [ ] Publier une politique de confidentialité spécifique à Index Canada sur une URL publique stable.
- [ ] Ajouter un accès à cette politique dans l'application.
- [ ] Inventorier les données réellement envoyées à Wix, Apple, Google et Stripe Web : coordonnées professionnelles, adresse, photos, identifiants techniques et données liées au paiement.
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
- [ ] Résoudre la demande de réinitialisation de la clé d'envoi Google Play et confirmer que le certificat local correspond au certificat d'importation attendu avant tout téléversement.
- [ ] Démarrage de l'AAB confirmé avec `APP_ENVIRONMENT=production` et une `API_BASE_URL` HTTPS non factice, sans clé Stripe.
- [ ] Google Play Billing reconnaît les deux produits annuels et le bouton Restaurer/Actualiser les achats rétablit le droit.
- [ ] Version installée et testée depuis le canal interne Google Play.
- [ ] Exigences de test fermé du compte vérifiées et satisfaites, si applicables.
- [ ] Politique de confidentialité, sécurité des données, accès à l'application, public cible, classification du contenu et déclarations requises complétés.
- [ ] Icône, bannière et captures conformes et représentatives de la version testée.
- [ ] Description FR et EN relue ; aucune promesse de qualification, de couverture nationale ou de fonctionnalité non démontrée.
- [ ] Déploiement progressif et procédure de retour arrière approuvés.

## 6. iOS / App Store — bloquant

- [ ] Adhésion Apple Developer et contrats App Store Connect actifs.
- [ ] **Bloquant financier confirmé —** Le contrat « applications payantes » est en attente d'informations de l'utilisateur. Ajouter le compte bancaire et compléter le formulaire Québec FP 2506-V ainsi que le questionnaire fiscal des États-Unis avant de recevoir des paiements.
- [ ] App ID `ca.indexcanada.app`, équipe, certificats et profils de provisionnement configurés.
- [ ] Archive Release signée avec les vraies valeurs de production.
- [ ] Démarrage de l'archive confirmé avec `APP_ENVIRONMENT=production` et une `API_BASE_URL` HTTPS non factice, sans clé Stripe.
- [ ] StoreKit reconnaît les deux produits annuels et Restaurer les achats rétablit le droit.
- [ ] Version installée et testée depuis TestFlight.
- [ ] `Info.plist` et `PrivacyInfo.xcprivacy` validés contre les SDK et comportements réels.
- [ ] Fiche App Privacy, public cible, classification et informations de révision complétées.
- [ ] Captures et métadonnées FR/EN représentatives de la version testée.
- [ ] Soumission App Store approuvée par la personne responsable du produit.

## 7. Exploitation et lancement — bloquant

- [ ] Responsables nommés pour Wix, Apple, Google, Stripe Web, confidentialité et support utilisateur.
- [ ] Alertes et procédure d'investigation définies pour les échecs de notification store, validation, inscription et envoi de média.
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
