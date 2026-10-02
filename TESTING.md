# Guide de tests

La stratégie actuelle protège surtout la logique déterministe de
l'application et du backend. Les tests n'appellent ni Wix, ni l'App Store, ni
Google Play, ni Stripe, ni Firebase en production. Ils sont nécessaires, mais
ne remplacent pas des achats sandbox sur iOS, des achats avec testeurs sous
licence Google Play et une intégration sur un environnement Wix isolé. Stripe
ne concerne que le parcours Web/legacy séparé lorsqu'il est encore déployé.

## Prérequis

- Flutter `3.47.4` et Dart `3.13.3`;
- JDK `17`, Gradle `8.14.5`, AGP `8.11.1` et KGP `2.2.21` pour Android;
- Node.js `18.19.0` pour les gates backend de CI/release;
- les versions verrouillées dans `pubspec.lock`.

```bash
flutter pub get --enforce-lockfile
```

## Contrôles locaux

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage --reporter expanded
npm test --prefix backend
```

Pour lancer un seul fichier :

```bash
flutter test test/services/data_service_test.dart
node backend/test/security-core.test.js
node backend/test/directory-pagination.test.js
```

Sur certains environnements Windows restreints, `node --test` peut échouer
avec `spawn EPERM`. L'exécution directe de chaque fichier conserve les mêmes
assertions `node:test` sans créer de sous-processus.

## État à vérifier pour chaque candidate

Les anciens totaux du plan ROI v1 ne décrivent plus la suite actuelle : les
tests Store Billing, les notifications Apple/Google et les changements de
forfait ont été ajoutés depuis. Pour éviter d'afficher un total rapidement
obsolète, la preuve d'une candidate est le résultat frais des quatre commandes
de contrôle local ci-dessus, puis des jobs GitHub Actions du commit exact. Une
suite ciblée verte ne permet pas d'annoncer la suite complète verte.

Au contrôle antérieur du 18 septembre 2026, le build Web release avait réussi,
y compris le contrôle de compatibilité Wasm. La couverture de lignes Flutter
était alors de 29,6 % (1 945 lignes couvertes sur 6 571 dans le fichier local
`coverage/lcov.info`). Le build et la couverture n'ont pas été recalculés pour
la version ROI v1 et ne doivent pas être présentés comme des résultats actuels.

La couverture reste faible et ne doit pas être présentée comme une garantie
de qualité « niveau production ». Elle mesure les lignes exercées, pas la qualité
des scénarios ni l'intégration avec les services externes.

Le poste Windows courant ne permet pas à lui seul de compiler et signer toutes
les plateformes. Les preuves distantes du commit fonctionnel `07e2197` sont :

- [Flutter CI #46](https://github.com/farouk60/index-canada-app/actions/runs/37016569680),
  succès;
- [Android Staging #7](https://github.com/farouk60/index-canada-app/actions/runs/36912587516),
  AAB 1.1.0 (27) signé et chiffré;
- [iOS Staging #2](https://github.com/farouk60/index-canada-app/actions/runs/37019413309),
  IPA 1.1.0 (27) signée/chiffrée et nettoyage réussi.

Le run [iOS Staging #1](https://github.com/farouk60/index-canada-app/actions/runs/37014876742)
a téléversé le build 27 avec succès auprès d'Apple, puis a échoué uniquement
pendant le nettoyage local. Le correctif `07e2197` a été validé sans
retéléverser le même build. Ces passages ne remplacent pas les achats sandbox,
les notifications réelles ni les essais de parcours sur appareils.

## Preuve historique Stripe Web/legacy du 22 septembre 2026

Avant la migration mobile vers Store Billing, un scénario Premium serveur à
serveur a été exécuté avec des données synthétiques sur le site séparé
`ImmIndex-Preprod` et le compte Stripe en mode test :

- création d'un checkout Premium à 4 999 cents CAD, puis répétition de la même
  requête avec réutilisation stricte du checkout et du PaymentIntent;
- confirmation Stripe avec une méthode de paiement fictive, résultat
  `succeeded`, montant reçu 4 999 cents et `livemode=false`;
- événement `payment_intent.succeeded` signé, livré au webhook Wix et sans
  livraison restante;
- finalisation unique avec profil `pending_review` et `isActive=false`;
- rejeu du même webhook et répétitions de `confirmPayment` sans second paiement
  ni second profil;
- nouvelle tentative de création après finalisation retournant
  `already_finalized=true`;
- suppression ciblée du profil et du checkout QA; seul le PaymentIntent de
  test demeure dans l'historique Stripe.

Une indisponibilité Wix transitoire (`Runtime is unreachable`) a été observée
après le paiement. La reprise a réutilisé le même PaymentIntent et la même
opération idempotente, sans recréer ni repayer le checkout.

Cette preuve couvre seulement le transport Stripe Web/legacy, sa finalisation,
la modération et son idempotence côté serveur. Elle ne valide ni StoreKit, ni
Google Play Billing, ni les restaurations, changements de forfait et
notifications des stores. Elle ne doit donc pas servir de preuve pour une
candidate mobile.

## Périmètre couvert

| Suite | Risque principal couvert |
|---|---|
| `test/core/`, `test/app_test.dart` | Démarrage déterministe, configuration et journalisation sans données sensibles |
| `test/core/config/mobile_store_policy_test.dart` | Garde anti-régression : aucune dépendance Stripe native, aucune PaymentSheet et aucun secret Stripe injecté dans les compilations mobiles |
| `test/core/bootstrap/app_bootstrap_test.dart` | Initialisation unique du listener IAP sur iOS/Android seulement et continuité après un échec non critique |
| `test/models/` | Parsing défensif des professionnels, catégories, partenaires, offres, coupons et avis |
| `test/data/` | Intégrité des villes canadiennes |
| `test/services/data_service_test.dart` | Contrat v2 Wix, parcours des curseurs, cache/rafraîchissement, concurrence, erreurs réseau et publication des seuls avis approuvés |
| `test/services/store_purchase_service_test.dart` | Catalogue annuel, prix localisés, checkout sans prix client, achat et acquittement après confirmation serveur, restauration, reprise au redémarrage, états pending/canceled/error, changements Google immédiats ou différés et refus fermé des événements incohérents |
| `test/pages/store_purchase_page_test.dart` | Informations d'abonnement, confidentialité, gestion de l'abonnement et EULA selon App Store ou Google Play |
| `test/pages/professional_registration_page_test.dart` | Forfait Basique gratuit, avantages et prix annuels localisés des stores dans le tunnel d'inscription |
| `test/services/review_verification_service_test.dart` | Anonymisation locale, anti-abus et purge des traces d'avis |
| `test/services/firebase_analytics_service_test.dart` | Contrat ROI fermé, absence de données personnelles, file bornée, reprise transitoire avec le même identifiant et non-blocage de l'interface |
| `test/pages/*analytics*`, `test/pages/roi_impression_pages_test.dart` | Attribution accueil/annuaire/détail et déclenchement uniquement après une action réussie |
| `test/widgets/engagement_visibility_tracker_test.dart`, `test/widgets/coupon_widget_test.dart` | Impression après visibilité continue à 50 %, défilement, cycle de vie, route masquée et copie de coupon réussie |
| `test/widgets/` | Rendu des images, états de repli et composants sans réseau réel |
| `backend/test/security-core.test.js` | Catalogue serveur, validation, idempotence, projections publiques, médias Wix sans Base64 persisté et compatibilité Stripe Web/legacy isolée |
| `backend/test/directory-pagination.test.js` | Pages Wix suivantes, curseurs opaques liés aux filtres, tailles bornées, ordre, propagation des erreurs et plafonds |
| `backend/test/store-purchase-core.test.js` | Validation Apple/Google, produits annuels, environnements, lignée Google hachée, politiques de changement de forfait, plan différé et refus des achats expirés/révoqués/incohérents |
| `backend/test/store-purchase-verifiers.test.js` | Adaptateurs Apple/Google et erreurs normalisées des fournisseurs sans persistance de preuve brute |
| `backend/test/store-notifications.test.js` | App Store Server Notifications et Google RTDN : renouvellement, changement différé, expiration, révocation, idempotence et prédécesseur remplacé |
| `backend/test/http-functions.test.js` | Contrats HTTP Wix v2, achats/restaurations Store Billing, notifications, saga Entitlement→Professionnel, reprise idempotente et compatibilité historique |
| `backend/test/engagement-report*.test.js` | Agrégats ROI, ratios par emplacement, plafond de rapport, permission administrateur et exclusion de la facturation |
| `backend/test/engagement-maintenance.test.js` | Purges bornées, lots partiels, signalement du reliquat et nettoyage des limiteurs expirés |

Les tests de widget utilisent des données locales. Ils ne doivent pas
initialiser de service externe ni dépendre de l'état d'un site Wix.

## Scénarios de préproduction obligatoires

Utiliser des données synthétiques, un environnement Wix isolé, le sandbox
Apple et les testeurs sous licence Google Play :

1. charger plus de 1 000 éléments dans une collection de test et confirmer
   l'absence de troncature;
2. vérifier qu'un dépassement de plafond échoue explicitement au lieu de servir
   un résultat partiel;
3. exercer `/categories`, `/professionals`, `/reviews`, `/partners` et
   `/offers` sur au moins deux pages, vérifier `limit`, `has_more` et
   `next_cursor`, puis rejouer chaque filtre de `/professionals` et
   `professionalId` sur `/reviews`;
4. confirmer qu'un curseur malformé/non canonique ou associé à d'autres
   filtres est refusé, que le client détecte un curseur répété et qu'il n'y a
   ni doublon ni boucle lorsque des éléments sont masqués;
5. soumettre un avis et confirmer qu'il est invisible avant
   `isApproved=true` ou `moderationStatus=approved`;
6. soumettre une inscription avec images, puis vérifier dans Wix que
   `PaymentCheckouts` et `Professionnel` contiennent seulement des `fileUrl`
   Wix et des empreintes, sans `data:image/...;base64`;
7. vérifier que le forfait Basique crée un checkout gratuit sans ouvrir
   StoreKit ou Google Play et qu'il reste soumis à modération;
8. confirmer que le client mobile ne contient ni SDK/configuration Stripe, ni
   clé Apple/Google, compte de service, reçu ou secret; le prix Premium/En
   Vedette doit venir du produit annuel retourné par le store;
9. sur iOS sandbox, acheter chaque forfait payant puis couvrir achat en attente,
   annulation, erreur store, reprise réseau, redémarrage et restauration sur un
   autre appareil connecté au même compte Apple;
10. avec un testeur Google Play, couvrir les mêmes états et confirmer qu'un
    jeton sans `purchaseId` facultatif est quand même vérifié côté serveur;
11. refuser sans droit tout produit, application, compte obscurci,
    environnement, preuve, expiration ou révocation qui ne correspond pas au
    checkout, puis vérifier qu'aucune preuve brute n'est persistée ou journalisée;
12. vérifier Premium→En Vedette avec proratisation immédiate, puis En
    Vedette→Premium en mode différé : l'ancien forfait reste actif avec
    `pendingPlanId` jusqu'au renouvellement, puis la bascule se fait sans créer
    un second droit ou profil;
13. rejouer les notifications Apple/Google et les événements de l'ancien jeton
    après remplacement; renouvellement, annulation, grâce, suspension,
    expiration, remboursement et révocation doivent être idempotents;
14. confirmer que le store n'est acquitté qu'après une réponse serveur valide;
    pending/canceled/error ou une réponse incohérente doivent autoriser une
    reprise sûre sans écraser un checkout actif;
15. interrompre puis reprendre un checkout avec la même requête et confirmer
    qu'il n'existe ni double paiement, ni double profil, ni média public orphelin;
16. forcer un échec d'upload/persistance et vérifier les journaux du nettoyage
   compensatoire; son échec doit être surveillé et traité;
17. confirmer que les inscriptions gratuites et payantes restent
   `pending_review`, `isActive=false` et invisibles dans le répertoire jusqu'à
   une approbation humaine dans Wix;
18. si le parcours Web/legacy Stripe est conservé, le tester séparément avec
    clés de test et webhook signé; vérifier aussi que le client mobile ne peut
    pas atteindre ce parcours;
19. valider les parcours bilingues et les largeurs mobile/desktop;
20. rejouer un même événement ROI avec le même identifiant et confirmer une
    seule écriture; réutiliser cet identifiant avec un contenu différent et
    confirmer le refus; vérifier également le rejet de `categoryId`, de tout
    champ inconnu et de toute donnée personnelle;
21. vérifier qu'un membre ou visiteur ne peut pas appeler le rapport ROI
    administrateur, puis contrôler ses ratios sur un petit jeu connu;
22. exécuter séparément les deux tâches de purge sur une copie de données,
    mesurer leur durée près de 25 lots et confirmer le signalement d'un reliquat;
23. mesurer le débit public de `engagementEvent` derrière la protection edge
    prévue et confirmer que ses données non vérifiées ne déclenchent ni
    facturation ni promesse de résultat;
24. simuler une erreur transitoire cliente et confirmer le même `eventId` lors
    des deux reprises maximales, puis une erreur 4xx sans nouvelle tentative.

Conserver l'identifiant de requête renvoyé par l'API pour relier un échec aux
journaux Wix sans journaliser de contenu personnel.

## GitHub Actions

Le workflow `.github/workflows/ci.yml` est configuré sur les demandes de
changement, les envois vers `main` et le lancement manuel. Il doit :

1. refuser les fichiers sensibles suivis, les motifs de secrets connus et toute
   réintroduction de Stripe natif dans le client mobile;
2. exécuter les tests backend avec Node.js 22;
3. imposer le format de `lib/` et `test/`;
4. exécuter `flutter analyze` sans tolérer avertissement ou information;
5. exécuter les tests Flutter avec couverture;
6. compiler Web en release;
7. compiler un bundle Android release volontairement non signé et vérifier
   qu'il ne contient pas de signature;
8. compiler iOS release sans signature sur un exécuteur macOS.

La détection de secrets est un filet minimal. Elle ne scanne pas correctement
tout l'historique Git et ne remplace ni Gitleaks, ni la rotation immédiate d'un
secret exposé.

## Priorités QA suivantes

- tests d'intégration du backend Wix et du Media Manager;
- achats sandbox StoreKit et Google Play avec notifications serveur réelles,
  restaurations, changements de forfait et reprises réseau;
- parcours de bout en bout Android/iOS sur appareils réels; si le Web/legacy
  Stripe est conservé, le valider dans une campagne distincte;
- tests d'accessibilité et régressions visuelles aux points de rupture;
- tests de charge et d'indexation des cinq routes v2 déjà utilisées, puis
  surveillance des appels résiduels à `/data` avant son retrait; `/data` reste
  un contrat de compatibilité temporaire, pas l'API cible;
- protection edge/CDN et, si possible, attestation d'application pour réduire
  les événements ROI distribués ou usurpés avant la production;
- outbox analytique persistante pour conserver les derniers événements lors
  d'une fermeture brutale de l'application;
- hausse progressive de la couverture sur les parcours critiques avant de
  fixer un seuil bloquant.
