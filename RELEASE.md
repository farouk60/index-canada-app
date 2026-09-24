# Guide de mise en production Android et iOS

## Statut actuel : NO-GO production

Le dépôt permet de vérifier et de compiler l'application, mais il ne démontre pas encore qu'une version distribuable fonctionne de bout en bout avec Wix et Stripe. Une publication ne doit être autorisée qu'après la fermeture de tous les critères bloquants de ce document et de [`production_checklist.md`](production_checklist.md).

État vérifié dans le dépôt :

- version Flutter candidate : `1.1.0+25` ;
- versions déjà utilisées dans les stores : iOS `1.0.4 (24)` et Android `1.0.3 (21)` ;
- identifiant Android et iOS : `ca.indexcanada.app` ;
- nom affiché : `Index Canada` ;
- la CI Android produit volontairement un AAB **non signé et non distribuable** ;
- la CI iOS compile avec `--no-codesign` et ne produit donc pas une livraison App Store ;
- Firebase Analytics est un service désactivé (stub) : aucun suivi Firebase ne doit être annoncé ;
- un paiement Premium serveur à serveur est consigné comme réussi en préproduction Wix/Stripe de test, avec webhook et rejeu idempotent; les parcours natifs Android/iOS restent non validés.

## 1. Critères bloquants avant une release

### 1.1 Backend Wix et données

- Déployer et valider le backend selon [`WIX_DEPLOYMENT.md`](WIX_DEPLOYMENT.md).
- Vérifier les collections, leurs champs, leurs index et leurs permissions minimales en production.
- Vérifier que les fichiers sont enregistrés dans Wix Media Manager et qu'aucune image encodée en Base64 n'est persistée dans une collection.
- Valider la pagination réelle des professionnels, catégories, avis, partenaires et offres, y compris au-delà d'une première page de résultats.
- Vérifier les limites de sécurité prévues pour chaque collection et le comportement explicite quand une limite est atteinte.
- Installer dans le Package Manager Wix la version exacte `stripe@22.6.2`, identique à `backend/package-lock.json`, puis prouver son chargement en préproduction.
- Confirmer que toute inscription, gratuite ou payante, reste inactive et `pending_review` jusqu'à l'approbation humaine dans Wix.
- Valider les routes v2 déjà livrées (`/categories`, `/professionals`,
  `/reviews`, `/partners`, `/offers`) sur plusieurs pages et avec chaque
  filtre; conserver `GET /data` uniquement comme compatibilité v1 mesurée.
- Vérifier en préproduction les index Wix des états de visibilité, de la
  catégorie, du professionnel associé et de l'ordre `_id`; corriger tout scan
  lent ou erreur d'index avant promotion.
- Configurer les secrets Wix/Stripe côté serveur seulement. Aucun secret Stripe ou Wix ne doit être intégré à l'application Flutter.

### 1.2 Paiement Stripe

- Configurer l'URL et le secret du webhook Stripe de production dans Wix.
- Vérifier qu'un paiement réussi ne publie pas automatiquement le profil et ne contourne pas la modération.
- Tester sur un environnement de préproduction : forfait gratuit, paiement réussi, paiement refusé, annulation, authentification 3-D Secure, webhook retardé et webhook envoyé plusieurs fois.
- Confirmer l'idempotence : une relance ne doit ni créer plusieurs paiements ni plusieurs profils.
- Vérifier que le montant, la devise, le forfait et les capacités sont toujours déterminés côté serveur.
- Tester la restauration après une erreur d'envoi de média ou de persistance Wix.
- Ne pas annoncer de paiement Web : le paiement payant est volontairement indisponible sur Web tant qu'une intégration Stripe Web dédiée n'existe pas.

### 1.3 Validation fonctionnelle et appareils

- Exécuter les parcours critiques sur au moins un appareil Android réel et un iPhone réel : démarrage, changement de langue, recherche, filtres, favoris, ouverture des liens externes, inscription gratuite et inscription payante.
- Tester les autorisations caméra et photos : accord, refus et refus permanent.
- Tester réseau lent, absence de réseau, erreur serveur et reprise après interruption.
- Vérifier l'accessibilité, les petites largeurs d'écran, les grandes tailles de texte et les deux langues.
- Consigner les résultats, versions d'OS et preuves. Les tests unitaires, widgets et compilations CI ne remplacent pas ces tests de bout en bout.

### 1.4 Confidentialité et conformité

- Publier une politique de confidentialité propre à Index Canada, accessible dans l'application et sur une URL publique stable.
- Inventorier les données réellement envoyées à Wix, Stripe et tout autre prestataire, puis faire correspondre exactement les déclarations Google Play « Sécurité des données » et App Store « App Privacy ».
- Définir la conservation, la suppression et le support des demandes d'accès/suppression des données.
- Vérifier si le parcours d'inscription constitue une création de compte au sens des politiques des stores ; si oui, fournir les mécanismes de suppression exigés.
- Faire valider les conditions d'utilisation et la politique de confidentialité par une personne compétente avant publication.

## 2. Préparer une version

1. Fermer les critères bloquants ci-dessus.
2. Choisir un numéro de version et augmenter `version:` dans `pubspec.yaml`. Ne jamais réutiliser un code de version déjà envoyé à un store.
3. Geler l'URL HTTPS de production et la clé Stripe **publique** correspondant
   au bon compte. La validation de démarrage exige une URL réelle; Android et
   iOS exigent une clé `pk_live_`. Le Web peut omettre cette clé tant que le
   paiement payant y reste désactivé.
4. Exécuter l'analyse statique et tous les tests automatisés.
5. Compiler les deux plateformes avec la configuration de production.
6. Installer les artefacts signés sur de vrais appareils et rejouer le contrôle de fumée.
7. Distribuer d'abord sur un canal interne ou bêta, puis obtenir une approbation explicite avant la production.

## 3. Android

### 3.1 Prérequis

- Flutter et Android SDK compatibles avec le projet ;
- JDK 17 ;
- application créée dans Google Play Console avec le package `ca.indexcanada.app` ;
- Play App Signing activé ;
- clé d'envoi sauvegardée dans un gestionnaire de secrets sécurisé.

### 3.2 Configurer la signature

Créer une clé d'envoi si aucune clé officielle n'existe déjà :

```powershell
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Créer localement `android/key.properties` :

```properties
storePassword=VALEUR_SECRETE
keyPassword=VALEUR_SECRETE
keyAlias=upload
storeFile=CHEMIN_VERS_UPLOAD_KEYSTORE
```

Ces deux fichiers ne doivent jamais être versionnés. La tâche Gradle de
distribution exige une configuration de signature valide. L'option CI
`indexCanada.allowUnsignedRelease=true` sert uniquement à vérifier la
compilation; son résultat ne doit jamais être envoyé à Google Play.

### 3.3 Compiler l'AAB distribuable

Depuis la racine du dépôt, remplacer les valeurs d'exemple par les valeurs de production approuvées :

```powershell
flutter clean
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build appbundle --release --dart-define=APP_ENVIRONMENT=production --dart-define=API_BASE_URL=https://VOTRE_DOMAINE/_functions --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_VOTRE_CLE_PUBLIQUE
```

Artefact attendu : `build/app/outputs/bundle/release/app-release.aab`.

Avant l'envoi, vérifier la signature, installer la version par un canal de test Google Play et confirmer que l'application utilise bien le backend de production prévu.

Les `--dart-define` sont injectés pendant la compilation, mais
`AppConfig.validateForRuntime` les contrôle au démarrage de l'application, pas
pendant `flutter build`. Une compilation réussie ne prouve donc pas la
configuration : l'application native de production refuse de démarrer si
l'URL est non HTTPS/factice ou si la clé publique n'est pas une `pk_live_`.

## 4. iOS

### 4.1 Prérequis

- Mac avec une version de Xcode compatible ;
- adhésion Apple Developer active ;
- App ID `ca.indexcanada.app`, certificats et profils de provisionnement valides ;
- accès App Store Connect et contrats requis acceptés.

### 4.2 Compiler et signer

1. Ouvrir `ios/Runner.xcworkspace` dans Xcode.
2. Sélectionner l'équipe de signature du target `Runner` et vérifier le Bundle Identifier.
3. Vérifier les descriptions d'accès aux photos et à la caméra ainsi que `PrivacyInfo.xcprivacy` contre les SDK réellement embarqués.
4. Compiler une archive Release avec les valeurs de production approuvées, puis la distribuer vers TestFlight.

Une compilation CI avec `--no-codesign` confirme seulement que le code peut être compilé ; elle n'est pas soumissible à l'App Store.

## 5. Permissions réellement déclarées

Android déclare actuellement :

- `INTERNET` ;
- `ACCESS_NETWORK_STATE` ;
- `CAMERA`.

Android ne déclare pas de permission de localisation, d'appel téléphonique ou de stockage. La galerie utilise le sélecteur système ; la carte et le téléphone sont ouverts par des applications externes.

iOS fournit actuellement des descriptions d'usage pour la caméra et la photothèque. Aucune description de localisation n'est déclarée. Toute nouvelle permission doit être justifiée, testée et répercutée dans les déclarations de confidentialité avant publication.

## 6. Déploiement progressif et retour arrière

- Android : test interne, puis test fermé si applicable au compte, puis déploiement progressif après validation.
- iOS : TestFlight interne/externe avant soumission App Store.
- Conserver la version précédente disponible pour un retour arrière côté store.
- Prévoir une procédure pour désactiver un forfait, un webhook ou une fonctionnalité côté serveur sans publier immédiatement une nouvelle application.
- Surveiller les erreurs Wix/Stripe, Android vitals, les métriques App Store et les demandes support. Firebase Crashlytics et Firebase Analytics ne sont pas actifs dans l'état actuel.

## 7. Approbation finale

La décision GO exige au minimum :

- un backend Wix de production validé selon `WIX_DEPLOYMENT.md` ;
- un paiement Stripe réel réussi et rapproché avec le webhook ;
- des parcours critiques réussis sur appareils Android et iOS réels ;
- des artefacts signés installés depuis les canaux bêta des stores ;
- des déclarations de confidentialité approuvées et cohérentes avec le comportement observé ;
- aucun défaut bloquant ouvert et une personne responsable identifiée pour le support du lancement.
