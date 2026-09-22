# Guide de tests

La stratégie actuelle protège surtout la logique déterministe de
l'application et du backend. Les tests n'appellent ni Wix, ni Stripe, ni
Firebase en production. Ils sont nécessaires, mais ne remplacent pas des essais
d'intégration sur un environnement Wix/Stripe isolé.

## Prérequis

- Flutter `3.47.4` et Dart `3.13.3`;
- JDK `17`, Gradle `8.14.5`, AGP `8.11.1` et KGP `2.2.21` pour Android;
- Node.js `22` pour les tests backend en CI;
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

## État vérifié localement

Au dernier contrôle local du 18 septembre 2026 :

- suite Flutter complète : 106 tests réussis sur 106;
- 45 tests backend réussis (26 sécurité/paiement/médias, 9 pagination et
  10 contrats HTTP Wix v2);
- analyse Flutter stricte : aucune anomalie;
- build Web release réussi, y compris le contrôle de compatibilité Wasm;
- couverture de lignes Flutter : 29,6 % (1 945 lignes couvertes sur 6 571
  dans le fichier local `coverage/lcov.info`).

La couverture reste faible et ne doit pas être présentée comme une garantie
de qualité « niveau production ». Elle mesure les lignes exercées, pas la qualité
des scénarios ni l'intégration avec les services externes.

L'Android SDK n'est pas installé sur la machine utilisée pour ce contrôle : le
bundle Android n'y a donc pas été compilé. Une compilation iOS n'est pas
possible sous Windows. Les jobs GitHub Actions correspondants sont configurés,
mais n'ont pas été exécutés ici et ne doivent pas être annoncés comme réussis
avant un vrai passage de CI.

## Preuve d'intégration préproduction du 22 septembre 2026

Un scénario Premium serveur à serveur a été exécuté avec des données
synthétiques sur le site séparé `ImmIndex-Preprod` et le compte Stripe en mode
test :

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

Cette preuve ferme le transport signé, la finalisation payée, la modération et
l'idempotence côté serveur. Elle ne remplace pas les scénarios Basic, refus,
annulation, 3-D Secure, médias, reprise réseau depuis l'application ni les tests
sur appareils Android et iOS réels.

## Périmètre couvert

| Suite | Risque principal couvert |
|---|---|
| `test/core/`, `test/app_test.dart` | Démarrage déterministe, configuration et journalisation sans données sensibles |
| `test/models/` | Parsing défensif des professionnels, catégories, partenaires, offres, coupons et avis |
| `test/data/` | Intégrité des villes canadiennes |
| `test/services/data_service_test.dart` | Contrat v2 Wix, parcours des curseurs, cache/rafraîchissement, concurrence, erreurs réseau et publication des seuls avis approuvés |
| `test/services/stripe_native_payment_service_test.dart` | Contrat HTTP, forfaits serveur, images, confirmations et refus du paiement Web |
| `test/services/review_verification_service_test.dart` | Anonymisation locale, anti-abus et purge des traces d'avis |
| `test/widgets/` | Rendu des images, états de repli et composants sans réseau réel |
| `backend/test/security-core.test.js` | Catalogue serveur, validation, jetons, idempotence, liaison Stripe, projections publiques et médias Wix sans Base64 persisté |
| `backend/test/directory-pagination.test.js` | Pages Wix suivantes, curseurs opaques liés aux filtres, tailles bornées, ordre, propagation des erreurs et plafonds |
| `backend/test/http-functions.test.js` | Contrats HTTP Wix v2, filtres actifs, projections publiques, alias historiques, codes d'erreur, OPTIONS et méthodes refusées |

Les tests de widget utilisent des données locales. Ils ne doivent pas
initialiser de service externe ni dépendre de l'état d'un site Wix.

## Scénarios de préproduction obligatoires

Utiliser des données synthétiques et les clés Stripe de test :

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
7. interrompre puis reprendre un checkout avec la même requête et confirmer
   qu'il n'existe ni double paiement, ni double profil, ni média public orphelin;
8. forcer un échec d'upload/persistance et vérifier les journaux du nettoyage
   compensatoire; son échec doit être surveillé et traité;
9. envoyer deux fois le même événement webhook et confirmer que le résultat
   fonctionnel est unique;
10. tester montant, devise, métadonnées ou signature Stripe invalides;
11. confirmer que les inscriptions gratuites et payantes restent
   `pending_review`, `isActive=false` et invisibles dans le répertoire jusqu'à
   une approbation humaine dans Wix;
12. valider les parcours bilingues et les largeurs mobile/desktop;
13. vérifier que le Web refuse les forfaits payants avant tout checkout Stripe.

Conserver l'identifiant de requête renvoyé par l'API pour relier un échec aux
journaux Wix sans journaliser de contenu personnel.

## GitHub Actions

Le workflow `.github/workflows/ci.yml` est configuré sur les demandes de
changement, les envois vers `main` et le lancement manuel. Il doit :

1. refuser les fichiers sensibles suivis et les motifs de secrets connus;
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
- tests Stripe en mode test avec webhook réel et reprises réseau;
- parcours de bout en bout Android/iOS sur appareils réels;
- tests d'accessibilité et régressions visuelles aux points de rupture;
- tests de charge et d'indexation des cinq routes v2 déjà utilisées, puis
  surveillance des appels résiduels à `/data` avant son retrait; `/data` reste
  un contrat de compatibilité temporaire, pas l'API cible;
- hausse progressive de la couverture sur les parcours critiques avant de
  fixer un seuil bloquant.
