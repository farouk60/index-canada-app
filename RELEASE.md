# Guide de mise en production Android et iOS

## Statut actuel : NO-GO production

La version candidate migre les achats numériques mobiles vers StoreKit et Google Play Billing. Elle ne doit pas être publiée avant la validation de bout en bout des achats, restaurations, renouvellements, expirations et révocations avec le backend Wix. Stripe demeure réservé au Web et aux anciens clients compatibles.

État vérifié dans le dépôt :

- version Flutter cible : `1.1.0+26` ;
- versions déjà utilisées dans les stores : iOS `1.0.4 (24)` et Android `1.0.3 (21)` ;
- identifiant Android et iOS : `ca.indexcanada.app` ;
- nom affiché : `Index Canada` ;
- la CI Android produit volontairement un AAB **non signé et non distribuable** ;
- la CI iOS compile avec `--no-codesign` et ne produit donc pas une livraison App Store ;
- Firebase Analytics est un service désactivé (stub) : aucun suivi Firebase ne doit être annoncé ;
- le build iOS `1.1.0 (25)` validé par TestFlight contient encore l'ancien parcours Stripe natif et ne doit pas être soumis ;
- le build `26` doit remplacer Stripe natif par les produits annuels `ca.indexcanada.app.premium.annual` et `ca.indexcanada.app.professional.annual`.

## 1. Critères bloquants avant une release

### 1.1 Backend Wix et données

- Déployer et valider le backend selon [`WIX_DEPLOYMENT.md`](WIX_DEPLOYMENT.md).
- Vérifier les collections, leurs champs, leurs index et leurs permissions minimales en production.
- Vérifier que les fichiers sont enregistrés dans Wix Media Manager et qu'aucune image encodée en Base64 n'est persistée dans une collection.
- Valider la pagination réelle des professionnels, catégories, avis, partenaires et offres, y compris au-delà d'une première page de résultats.
- Vérifier les limites de sécurité prévues pour chaque collection et le comportement explicite quand une limite est atteinte.
- Installer dans le Package Manager Wix les versions exactes verrouillées dans `backend/package-lock.json` : `stripe@22.6.2`, `@apple/app-store-server-library@3.1.0`, `@googleapis/androidpublisher@38.0.0` et `google-auth-library@10.5.0`, puis prouver leur chargement en préproduction.
- Confirmer que toute inscription, gratuite ou payante, reste inactive et `pending_review` jusqu'à l'approbation humaine dans Wix.
- Valider les routes v2 déjà livrées (`/categories`, `/professionals`,
  `/reviews`, `/partners`, `/offers`) sur plusieurs pages et avec chaque
  filtre; conserver `GET /data` uniquement comme compatibilité v1 mesurée.
- Vérifier en préproduction les index Wix des états de visibilité, de la
  catégorie, du professionnel associé et de l'ordre `_id`; corriger tout scan
  lent ou erreur d'index avant promotion.
- Configurer les secrets Apple, Google, Wix et Stripe côté serveur seulement. Aucun secret ne doit être intégré à l'application Flutter.

### 1.2 Abonnements Apple et Google

- Créer dans App Store Connect et Google Play les deux abonnements annuels avec exactement les identifiants `ca.indexcanada.app.premium.annual` et `ca.indexcanada.app.professional.annual`.
- Valider chaque transaction côté serveur auprès d'Apple ou Google avant d'accorder le droit Premium ou En Vedette.
- Ne jamais accepter le prix, le produit, l'expiration, l'état ou le jeton comme une preuve fournie uniquement par le client.
- Tester : achat réussi, achat en attente, refus, annulation, restauration, renouvellement, expiration, remboursement/révocation, changement de formule, réseau interrompu et notification rejouée.
- Confirmer l'idempotence : une même transaction ou notification ne crée ni double droit, ni double profil, ni double événement financier.
- Vérifier qu'un abonnement actif ne publie pas automatiquement le profil et ne contourne jamais la modération Wix.
- Configurer App Store Server Notifications V2 et Google Real-time Developer Notifications vers les routes serveur prévues.
- Conserver Stripe uniquement pour le Web/legacy ; aucun PaymentSheet, schéma `flutterstripe` ou clé Stripe ne doit être requis par le binaire Android/iOS.

### 1.3 Validation fonctionnelle et appareils

- Exécuter les parcours critiques sur au moins un appareil Android réel et un iPhone réel : démarrage, changement de langue, recherche, filtres, favoris, ouverture des liens externes, inscription gratuite et inscription payante.
- Tester les autorisations caméra et photos : accord, refus et refus permanent.
- Tester réseau lent, absence de réseau, erreur serveur et reprise après interruption.
- Vérifier l'accessibilité, les petites largeurs d'écran, les grandes tailles de texte et les deux langues.
- Consigner les résultats, versions d'OS et preuves. Les tests unitaires, widgets et compilations CI ne remplacent pas ces tests de bout en bout.

### 1.4 Confidentialité et conformité

- Publier une politique de confidentialité propre à Index Canada, accessible dans l'application et sur une URL publique stable.
- Inventorier les données réellement envoyées à Wix, Apple, Google, Stripe Web et tout autre prestataire, puis faire correspondre exactement les déclarations Google Play « Sécurité des données » et App Store « App Privacy ».
- Définir la conservation, la suppression et le support des demandes d'accès/suppression des données.
- Vérifier si le parcours d'inscription constitue une création de compte au sens des politiques des stores ; si oui, fournir les mécanismes de suppression exigés.
- Faire valider les conditions d'utilisation et la politique de confidentialité par une personne compétente avant publication.

## 2. Préparer une version

1. Fermer les critères bloquants ci-dessus.
2. Choisir un numéro de version et augmenter `version:` dans `pubspec.yaml`. Ne jamais réutiliser un code de version déjà envoyé à un store.
3. Geler l'URL HTTPS de production. Les binaires Android et iOS ne reçoivent aucune clé Stripe ni aucun secret Apple/Google ; leurs achats utilisent les SDK des stores et la validation serveur.
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

Sous Windows, la commande suivante automatise la génération du keystore, de
son mot de passe local et du certificat public PEM à transmettre à Google Play :

```powershell
.\tool\provision_android_upload_key.ps1
```

Le script refuse d'écraser une clé existante. Il conserve le keystore et
`android/key.properties` dans les chemins déjà ignorés par Git, sans afficher
le mot de passe dans la sortie. La commande manuelle équivalente est :

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
flutter build appbundle --release --dart-define=APP_ENVIRONMENT=production --dart-define=API_BASE_URL=https://VOTRE_DOMAINE/_functions
```

Artefact attendu : `build/app/outputs/bundle/release/app-release.aab`.

Avant l'envoi, vérifier la signature, installer la version par un canal de test Google Play et confirmer que l'application utilise bien le backend de production prévu.

Les `--dart-define` sont injectés pendant la compilation, mais
`AppConfig.validateForRuntime` les contrôle au démarrage de l'application, pas
pendant `flutter build`. Une compilation réussie ne prouve donc pas la
configuration : l'application native de production refuse de démarrer si
l'URL est non HTTPS ou factice.

## 4. iOS

### 4.1 Prérequis

- Mac avec une version de Xcode compatible ;
- adhésion Apple Developer active ;
- App ID `ca.indexcanada.app`, certificats et profils de provisionnement valides ;
- accès App Store Connect et contrats requis acceptés.
- compte bancaire et formulaires fiscaux App Store Connect complétés pour les abonnements payants.

### 4.2 Compiler et signer

La génération reproductible utilise le workflow manuel GitHub Actions
`iOS Release`. Il ne s'exécute que depuis `main` et attend quatre secrets
chiffrés dans le dépôt :

- `IOS_DISTRIBUTION_P12_BASE64` ;
- `IOS_DISTRIBUTION_P12_PASSWORD` ;
- `IOS_APP_STORE_PROFILE_BASE64` ;
- `IOS_ARTIFACT_ENCRYPTION_PASSWORD`.

Le workflow vérifie l'équipe `K94TPPGBZS`, le Bundle ID
`ca.indexcanada.app`, le profil `Index Canada – App Store (Release
2026-2027)`, sa date d'expiration et le certificat qu'il contient. Il crée un
trousseau temporaire, produit l'IPA, vérifie sa signature puis chiffre l'IPA
en AES-256 avant de publier l'artefact pendant un jour. L'IPA brute, le
trousseau et les fichiers de signature temporaires sont ensuite supprimés du
runner.

Si l'option d'envoi TestFlight est activée, trois secrets App Store Connect
supplémentaires sont obligatoires : `ASC_KEY_ID`, `ASC_ISSUER_ID` et
`ASC_PRIVATE_KEY_P8_BASE64`.

Pour une compilation manuelle sur Mac :

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
- Surveiller les erreurs Wix, les validations Apple/Google, les notifications de renouvellement, Android vitals, les métriques App Store et les demandes support. Surveiller Stripe séparément pour le Web/legacy.

## 7. Approbation finale

La décision GO exige au minimum :

- un backend Wix de production validé selon `WIX_DEPLOYMENT.md` ;
- un achat réel ou sandbox validé et rapproché sur chaque store, incluant restauration et révocation ;
- des parcours critiques réussis sur appareils Android et iOS réels ;
- des artefacts signés installés depuis les canaux bêta des stores ;
- des déclarations de confidentialité approuvées et cohérentes avec le comportement observé ;
- aucun défaut bloquant ouvert et une personne responsable identifiée pour le support du lancement.
