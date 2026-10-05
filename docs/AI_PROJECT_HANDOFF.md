# Index Canada — dossier de reprise pour une IA

Dernière consolidation : **2 octobre 2026**

Base fonctionnelle auditée : **07e2197608495733e0f9b89ac996295742067573**

Branche auditée : **candidate/store-billing-entitlements-2026-09-28**

Ce document permet à un humain ou à une nouvelle IA de reprendre le projet sans
reconstruire son historique depuis les conversations. Il décrit le code, les
décisions, les opérations externes déjà réalisées, les preuves disponibles et
les risques encore ouverts.

Il ne remplace jamais une vérification directe. L'ordre de confiance est :

1. comportement observé sur le service externe et preuve datée;
2. workflow vert du commit exact;
3. tests du commit exact;
4. code courant;
5. documentation datée;
6. hypothèse ou souvenir.

## 1. Résumé exécutif

Index Canada est un annuaire bilingue FR/EN de professionnels, partenaires et
offres au Canada. Le client est une application Flutter pour Android, iOS et
Web. Wix sert de CMS, de back-office de modération et de backend Velo.

L'évolution majeure de septembre 2026 est la migration des paiements mobiles :

- le forfait Basique reste gratuit;
- Premium et En Vedette utilisent StoreKit et Google Play Billing;
- Stripe a été retiré du binaire mobile et reste seulement Web/legacy;
- le backend vérifie chaque transaction auprès du store avant d'accorder un
  droit;
- paiement et publication restent deux états séparés;
- les renouvellements, changements de formule, expirations, remboursements et
  révocations sont traités de manière idempotente.

La version source candidate est **1.1.0+28**. Les preuves externes du build 27
restent historiques jusqu'à la génération et au téléversement du build 28.

| Surface | État prouvé au 5 octobre 2026 |
| --- | --- |
| Android | 1.1.0 (27) disponible en test interne; source 1.1.0 (28) corrigée, CI et nouveau téléversement interne à terminer |
| iOS | 1.1.0 (27) acceptée au téléversement TestFlight; source 1.1.0 (28) corrigée, CI et nouveau téléversement TestFlight à terminer |
| Wix préproduction | backend Store Billing et Google RTDN publiés et testés au niveau transport |
| Wix production | Store Billing publié; catalogue v2, routes, preflights et refus de signatures invalides vérifiés |
| Google Play production | non publiée |
| App Store production | non soumise |
| Branche corrective | <code>fix/store-release-1.1.0-28</code>, créée depuis le vrai <code>origin/main</code> |
| main distant | candidate 28 fusionnée par la PR #10; correctifs finaux iOS/Android à fusionner après CI |

**Verdict actuel : bêta interne utile, mais NO-GO pour une publication publique.**

## 2. Ne pas confondre ces états

- « compilé » ne signifie pas « signé »;
- « signé » ne signifie pas « téléversé »;
- « téléversé dans TestFlight » ne signifie pas « publié dans l'App Store »;
- « test interne Google Play » ne signifie pas « production »;
- « notification Google Play de test reçue en HTTP 200 » ne prouve pas un
  achat, un renouvellement ou une révocation réels;
- « paiement réussi » ne signifie pas « profil approuvé »;
- « dépôt Wix synchronisé » ne signifie pas « site Wix publié »;
- « secret nommé dans Git » ne signifie pas que sa valeur existe ou est valide.

## 3. Écosystème des dépôts et environnements

### 3.1 Dépôts

| Dépôt | Rôle |
| --- | --- |
| <code>farouk60/index-canada-app</code> | dépôt public du client Flutter, backend de référence testé, workflows et documentation |
| <code>farouk60/index-canada-wix-preprod</code> | miroir déployable du backend Wix de préproduction |
| <code>farouk60/index-canada-wix-production</code> | dépôt privé du site Wix de production |

Le dossier <code>backend/</code> de ce dépôt est la source testée de la
candidate. Wix n'exécute pas automatiquement ce dossier : les fichiers
nécessaires doivent être synchronisés vers le dépôt Wix ciblé, puis le site Wix
doit être publié séparément. Comparer les fichiers ou leurs empreintes avant
toute publication.

### 3.2 Environnements

| Environnement | API | Usage |
| --- | --- | --- |
| development | injectée par <code>--dart-define</code> | travail local |
| staging | <code>https://immigrantindex.wixsite.com/website-1/_functions</code> | builds internes 27, achats sandbox/testeurs |
| production | <code>https://www.immigrantindex.com/_functions</code> | aucune utilisation publique autorisée avant le GO final |

Le site Wix de préproduction connu porte l'identifiant
<code>438a3bc3-d1ec-4967-98da-f48ae305fde7</code>. Le projet Google Cloud
préproduction utilisé pour RTDN est <code>index-immigrant-index-2025</code>.

## 4. Stack et points d'entrée

- Flutter 3.47.4 et Dart 3.13.x;
- Android : JDK 17, Gradle 8.14.5, AGP 8.11.1, Kotlin 2.2.21;
- iOS : Xcode/SDK 26 minimum dans les workflows, cible iOS 15.0;
- backend Wix Velo en modules JavaScript ESM;
- Node 18.19.0 dans les gates backend de release;
- package et Bundle ID : <code>ca.indexcanada.app</code>;
- version source candidate : <code>1.1.0+28</code>.

Points d'entrée :

- <code>lib/main.dart</code> : validation de configuration et lancement;
- <code>lib/core/bootstrap/app_bootstrap.dart</code> : services globaux et
  listener des achats avant l'interface;
- <code>lib/widgets/main_navigation.dart</code> : navigation principale;
- <code>lib/data_service.dart</code> : API annuaire et avis;
- <code>lib/services/store_purchase_service.dart</code> : achats mobiles;
- <code>backend/http-functions.js</code> : routes Wix publiques;
- <code>backend/security-core.js</code> : validation et projections;
- <code>backend/store-*.js</code> : droits, vérification et notifications.

L'application n'utilise pas Provider, BLoC ou Riverpod. Elle repose sur
StatefulWidget, ChangeNotifier, des services singletons et l'injection de
dépendances dans les tests.

## 5. Architecture des flux

### 5.1 Lecture du répertoire

    Pages Flutter
        → DataService
        → routes Wix /_functions
        → collections Wix privées
        → filtres et projections publiques
        → modèles Flutter

Routes v2 canoniques :

| Méthode | Route | Rôle |
| --- | --- | --- |
| GET | <code>/categories</code> | sous-catégories publiques |
| GET | <code>/professionals</code> | annuaire, recherche, ville, catégorie, vedette et IDs |
| GET | <code>/reviews</code> | avis approuvés d'un professionnel actif |
| GET | <code>/partners</code> | partenaires actifs et officiels |
| GET | <code>/offers</code> | offres actives |
| GET | <code>/paymentPlans</code> | catalogue public des forfaits |

La pagination utilise <code>limit</code> et un curseur opaque lié aux filtres.
Le client suit le curseur jusqu'à <code>has_more=false</code>, détecte un
curseur répété et déduplique les IDs. <code>GET /data</code> reste une
compatibilité v1; aucun nouveau parcours ne doit l'utiliser.

### 5.2 Professionnels en vedette

- l'accueil appelle <code>/professionals?featured=true</code>;
- Wix exige <code>isActive=true</code> et <code>sponsor=true</code>;
- <code>Professionnel.sponsor</code> est la source de vérité côté serveur et
  côté Flutter;
- Premium n'est pas En Vedette;
- le plan technique <code>professional</code> correspond au libellé commercial
  « En Vedette / Featured »;
- pour les profils gérés par Store Billing, le droit doit également être actif
  ou en période de grâce et non expiré.

Un repli legacy existe seulement pour les anciens payloads sans booléen
<code>sponsor</code>. Ne jamais réintroduire Premium dans cette inférence.

### 5.3 Avis

    AddReviewPage
        → ReviewVerificationService
        → POST /review
        → Reviews en attente
        → modération humaine Wix
        → GET /reviews

À la création :

- <code>moderationStatus="pending"</code>;
- <code>isApproved=false</code>;
- association canonique <code>professionalId</code>.

Un avis est public si <code>isApproved === true</code> ou si
<code>moderationStatus === "approved"</code>. La préproduction conserve un
schéma historique où <code>isApproved</code> a parfois été observé comme texte;
tant que ce champ n'est pas migré en booléen, renseigner aussi
<code>moderationStatus=approved</code>. Ne pas automatiser la publication des
avis sans une nouvelle décision produit.

Les alias <code>professionnelId</code>, <code>image</code> et l'ancien chemin
<code>/reviews/&lt;id&gt;</code> restent supportés pour la migration.

### 5.4 Inscription gratuite

Le forfait Basique n'initialise pas StoreKit ou Google Play. Les routes
historiquement nommées <code>createPaymentIntent</code> et
<code>confirmPayment</code> servent aussi le checkout gratuit signé.

Même gratuitement :

- la requête est validée et idempotente;
- les images sont envoyées au Wix Media Manager;
- le profil est créé avec <code>registrationStatus=pending_review</code>;
- <code>isActive=false</code> jusqu'à la modération.

### 5.5 Achat mobile payant

    catalogue serveur
        → produits localisés du store
        → checkout serveur
        → achat StoreKit/Google Play
        → preuve envoyée au backend
        → vérification officielle Apple/Google
        → droit Entitlements
        → profil en attente de modération
        → acquittement du store

Le client n'acquitte la transaction qu'après une réponse serveur cohérente. Une
erreur réseau ou métier laisse une reprise sûre possible sans nouvel achat.

Les produits canoniques sont :

- <code>ca.indexcanada.app.premium.annual</code>;
- <code>ca.indexcanada.app.professional.annual</code>.

Changements de formule Google autorisés :

- Premium vers Professional : immédiat avec
  <code>WITH_TIME_PRORATION</code>;
- Professional vers Premium : différé avec <code>DEFERRED</code>.

Les jetons de remplacement forment une lignée autour d'un droit racine
immuable. Seules des empreintes sont persistées; aucun purchase token brut ou
linked purchase token brut ne doit être conservé.

### 5.6 Notifications de stores

- Apple : <code>POST /appStoreServerNotificationV2</code>;
- Google : <code>POST /googlePlayRtdn</code>.

Google Pub/Sub fournit un jeton OIDC qui doit correspondre exactement à
l'audience et au compte de service Push autorisés. Le backend relit ensuite
l'abonnement auprès de Google Play. Les messages non liés aux abonnements sont
authentifiés puis ignorés sans mutation.

Les notifications sont idempotentes et ne contournent jamais la modération.

### 5.7 Mesure ROI

Le fichier <code>firebase_analytics_service.dart</code> porte un nom historique
mais n'utilise pas Firebase Analytics. Il transmet une télémétrie first-party
à <code>/engagementEvent</code> :

- dimensions fermées et aucune donnée personnelle;
- aucune requête de recherche brute;
- file mémoire de 100 événements;
- deux reprises au maximum pour erreurs transitoires;
- même identifiant idempotent lors d'une reprise;
- aucun blocage du parcours utilisateur.

Les rapports sont réservés aux administrateurs Wix. Ces métriques représentent
des interactions, pas des visiteurs uniques ou des ventes garanties.

## 6. Modèle commercial

| Forfait | Prix de référence serveur | Capacités |
| --- | ---: | --- |
| Basique | 0 CAD/an | profil, contacts, image principale, avis, visibilité standard |
| Premium | 49,99 CAD/an | Basique, galerie de 5 images, coupon, résumé mis en avant, support prioritaire |
| En Vedette | 119,99 CAD/an | Premium, accueil et résultats prioritaires, <code>sponsor=true</code> |

Sur mobile, le prix affiché et facturé vient toujours du store dans la devise
de l'utilisateur. Les montants du catalogue servent au contrat métier et au
parcours Web/legacy; ils ne remplacent pas le prix localisé du store.

La gratuité du Basique est un choix d'acquisition actuel. Ne pas la supprimer
sans données de conversion et sans revoir les deux stores, le backend, les
textes FR/EN et la stratégie commerciale.

## 7. Collections Wix

Collections métier :

- <code>Professionnel</code>;
- <code>Reviews</code>;
- <code>SousCategorie</code>;
- <code>Partenaires</code>;
- <code>OffresPartenaire</code>.

Collections techniques privées :

- <code>PaymentCheckouts</code>;
- <code>Entitlements</code>;
- <code>PaymentEvents</code>;
- <code>ApiRateLimits</code>;
- <code>EngagementEvents</code>.

Champs critiques de <code>Professionnel</code> :

- identité et contenu : title, subtitle, description, category,
  sousCategorie/sousCatgorie, ville et coordonnées;
- visibilité : <code>isActive</code>, <code>registrationStatus</code>,
  <code>moderationStatus</code>;
- commerce : <code>plan</code>, <code>sponsor</code>, dates de droit;
- médias : URL Wix de l'image et de la galerie;
- liens : siteWeb, lienFacebook, lienInstagram, lienWhatsapp et alias legacy.

Les fautes historiques telles que <code>sousCatgorie</code>,
<code>numroDeTlphone</code> et <code>lienWhatsapp</code> font encore partie de
la compatibilité. Ne pas les renommer ou supprimer sans migration complète.

## 8. Sécurité et secrets

Règles absolues :

- ne committer aucun secret;
- ne documenter que les noms;
- ne jamais injecter un secret Apple, Google ou Stripe par dart-define;
- ne jamais journaliser reçu, preuve, jeton, clé ou donnée personnelle;
- traiter toute valeur montrée dans un chat ou une capture comme compromise et
  la révoquer;
- conserver les collections privées et les projections en liste blanche.

### 8.1 Secrets Wix attendus

- <code>CHECKOUT_SIGNING_SECRET</code>;
- <code>CHECKOUT_SIGNING_SECRET_PREVIOUS</code>;
- <code>APPLE_APP_ID</code>;
- <code>APPLE_ROOT_CERTIFICATE_G1_BASE64</code>;
- <code>APPLE_ROOT_CERTIFICATE_G2_BASE64</code>;
- <code>APPLE_ROOT_CERTIFICATE_G3_BASE64</code>;
- <code>GOOGLE_PLAY_SERVICE_ACCOUNT_JSON</code>;
- <code>GOOGLE_RTDN_AUDIENCE</code>;
- <code>GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL</code>;
- <code>GOOGLE_RTDN_SUBSCRIPTION</code>;
- <code>STORE_ALLOW_SANDBOX</code>;
- <code>STRIPE_SECRET_KEY</code> et
  <code>STRIPE_WEBHOOK_SECRET</code> seulement si le Web/legacy reste actif.

### 8.2 Secrets GitHub Android

- <code>ANDROID_UPLOAD_KEYSTORE_BASE64</code>;
- <code>ANDROID_UPLOAD_STORE_PASSWORD</code>;
- <code>ANDROID_UPLOAD_KEY_PASSWORD</code>;
- <code>ANDROID_UPLOAD_KEY_ALIAS</code>;
- <code>ANDROID_UPLOAD_CERT_SHA256</code>;
- <code>ANDROID_ARTIFACT_ENCRYPTION_PASSWORD</code>.

Le téléversement Google Play n'utilise plus de clé JSON durable dans GitHub.
Le workflow échange le jeton GitHub OIDC contre un jeton Google de 900 secondes
au moyen du provider
<code>github-index-canada/index-canada-android-release</code> et du compte
<code>indexca-play-uploader-prod@index-immigrant-index-2025.iam.gserviceaccount.com</code>.
Le provider exige le dépôt, le propriétaire, <code>main</code>,
<code>workflow_dispatch</code>, le workflow Android exact et l'environnement
<code>mobile-staging</code>. Ne jamais réintroduire
<code>GOOGLE_PLAY_UPLOAD_SERVICE_ACCOUNT_JSON</code>.

### 8.3 Secrets GitHub iOS

- <code>IOS_DISTRIBUTION_P12_BASE64</code>;
- <code>IOS_DISTRIBUTION_P12_PASSWORD</code>;
- <code>IOS_APP_STORE_PROFILE_BASE64</code>;
- <code>IOS_ARTIFACT_ENCRYPTION_PASSWORD</code>;
- <code>ASC_KEY_ID</code>;
- <code>ASC_ISSUER_ID</code>;
- <code>ASC_PRIVATE_KEY_P8_BASE64</code>.

Variables GitHub de gate :

- <code>MOBILE_STAGING_APPROVED_SHA</code> verrouille les workflows staging;
- <code>MOBILE_PRODUCTION_APPROVED_SHA</code> doit être le SHA complet exact de
  <code>main</code> autorisé pour les deux workflows de production.

Une première clé API App Store Connect exposée accidentellement a été révoquée.
La clé de remplacement est stockée uniquement dans GitHub Secrets. Ne jamais
réutiliser une ancienne clé trouvée dans un historique, un téléchargement ou
une conversation.

## 9. Workflows CI/CD

| Fichier | Usage |
| --- | --- |
| <code>.github/workflows/ci.yml</code> | secrets, backend, format, analyse, tests, Web, Android non distribuable et iOS sans signature |
| <code>android-staging.yml</code> | AAB staging signé puis chiffré; upload Play manuel |
| <code>ios-staging.yml</code> | IPA staging signée/chiffrée; upload TestFlight optionnel |
| <code>android-release.yml</code> | AAB production 28 depuis main/SHA approuvé; build signé sans OIDC, artefact chiffré, puis job de téléversement interne optionnel avec WIF |
| <code>ios-release.yml</code> | IPA production depuis main seulement; upload TestFlight optionnel |

Les workflows staging sont verrouillés par :

- branche candidate exacte;
- version/build exacts;
- SHA approuvé hors branche;
- URL préproduction obligatoire;
- environnement GitHub <code>mobile-staging</code>;
- contrôles de secrets, backend, tests et signature;
- nettoyage des matériaux sensibles du runner.

Les artefacts signés sont chiffrés avant stockage. Un artefact temporaire ou
une courte rétention ne remplace pas le chiffrement.

Dans la release Android, seul <code>upload-google-play</code> possède
<code>id-token: write</code>. Il télécharge exclusivement le fichier
<code>.aab.enc</code>, vérifie les deux empreintes, déchiffre, contrôle ZIP,
signature, package <code>ca.indexcanada.app</code>, versionCode 28 et URL Wix
production, puis demande le jeton WIF immédiatement avant l'envoi. Le job
<code>signed-aab</code> reste limité à <code>contents: read</code>.

## 10. Preuves datées disponibles

- CI de la migration Store Billing :
  <https://github.com/farouk60/index-canada-app/actions/runs/36427764178>
- build Android staging signé 26 :
  <https://github.com/farouk60/index-canada-app/actions/runs/36615123605>
- build Android correctif 27 :
  <https://github.com/farouk60/index-canada-app/actions/runs/36912587516>
- upload TestFlight 1.1.0 (27), accepté par Apple avant une erreur de nettoyage :
  <https://github.com/farouk60/index-canada-app/actions/runs/37014876742>
- validation iOS staging finale du correctif, quatre jobs verts :
  <https://github.com/farouk60/index-canada-app/actions/runs/37019413309>
- testeurs Android internes :
  <https://play.google.com/apps/testing/ca.indexcanada.app>

Le run d'upload TestFlight rouge ne signifie pas que l'upload Apple a échoué :
Apple avait déjà accepté l'IPA. Le défaut de nettoyage a été corrigé par
<code>07e2197</code>, puis le workflow a été rejoué sans nouvel upload afin de
ne pas dupliquer le build 27.

## 11. Historique consolidé des changements

### 11.1 Fondation avant la candidate Store Billing

- <code>6fe4f30</code> : retrait de l'environnement de production suivi, CI,
  Dependabot et documentation sécurité/release;
- <code>2e833ff</code> : API Wix sécurisée, pagination bornée, projections
  publiques et paiements idempotents;
- <code>95f97db</code> : configuration Flutter centralisée, erreurs et logs;
- <code>d63e555</code> et <code>a290c43</code> : modernisation navigation,
  découverte, fiche et inscription;
- <code>d800e5c</code> : IDs Android/iOS et permissions de release;
- <code>636ba99</code> : compatibilité des avis et anciens IDs/chemins;
- <code>9db7f62</code>, <code>76bca90</code>, <code>7680001</code> : ROI
  first-party, rapport admin et maintenance;
- <code>7dc9093</code> : provisionnement sûr de la clé Android;
- <code>dfe7090</code>, <code>e1a8671</code>, <code>afb09ff</code> : IPA
  signée/chiffrée, upload TestFlight protégé et Xcode 26.

### 11.2 Les 22 commits fonctionnels de la candidate

| Commit | Changement |
| --- | --- |
| <code>80aeedc</code> | migration Stripe mobile vers Store Billing, droits, notifications et correctifs TestFlight |
| <code>6022a61</code> | thèmes natifs de lancement Android |
| <code>d1e19b0</code> | autorisation contrôlée des métadonnées SwiftPM générées |
| <code>4a74ca6</code> | intégration de la migration SwiftPM générée sur macOS |
| <code>0c8f464</code> | gestion sûre d'un diff de migration iOS vide |
| <code>9e860e5</code> | workflows staging Android/iOS isolés |
| <code>a6be142</code> | racines Apple séparées en trois secrets Wix |
| <code>5489ddc</code> | chargement statique des SDK store dans Wix |
| <code>75223fd</code> | contrat RTDN Google actuel et familles ignorées sûres |
| <code>5670df0</code> | retrait d'un exemple documentaire ressemblant à un secret |
| <code>74a9c7d</code> | provisionneur RTDN préproduction |
| <code>1c06e25</code> | durcissement du provisionneur RTDN |
| <code>6dbe846</code> | diagnostics OIDC sûrs et limités |
| <code>f7defb6</code> | classification des échecs de vérification Google |
| <code>5da0709</code> | récupération/vérification des certificats Google compatible Wix |
| <code>93db0f9</code> | validation correcte du certificat Android auto-signé |
| <code>a48b2b9</code> | tolérance contrôlée des changements générés attendus |
| <code>bcfa93b</code> | synchronisation des fichiers Flutter générés |
| <code>b400f7c</code> | enregistrement du plugin FFI Windows |
| <code>8452974</code> | build 27, sponsor canonique et vrais logos Instagram/WhatsApp |
| <code>56ebec7</code> | formatage Dart du build 27 |
| <code>07e2197</code> | fermeture du bloc de nettoyage iOS staging |

### 11.3 Correctifs UX issus des essais TestFlight

Le lot <code>80aeedc</code> comprend :

- Basique présenté comme Gratuit plutôt que 0 $/an;
- libellés de formulaire non superposés avec Dynamic Type;
- garde contre le double envoi;
- reprise idempotente après erreur transitoire;
- contraste lisible du sélecteur FR/EN;
- logos partenaires centrés avec proportions conservées;
- fiche et tunnel d'inscription modernisés.

Le lot <code>8452974</code> ajoute :

- les glyphes de marque Instagram et WhatsApp;
- des cibles tactiles de 48 px;
- le booléen <code>sponsor</code> comme source de vérité.

### 11.4 Changements externes non représentés uniquement par Git

- le backend Store Billing a été synchronisé et publié sur Wix préproduction;
- l'UI Wix préproduction a été réconciliée à la révision 14;
- les collections <code>Entitlements</code> et <code>PaymentEvents</code> ont
  été créées en préproduction, avec les champs Store Billing nécessaires;
- Google RTDN préproduction a été provisionné avec deux comptes de service
  séparés, un topic et un abonnement push OIDC;
- le test natif Google Play a été reçu en HTTP 200 sans backlog;
- les deux abonnements Google Play annuels ont été créés et activés au Canada,
  à 49,99 CAD et 119,99 CAD;
- un avis de test a été approuvé en préproduction et retrouvé par l'API;
- le champ <code>sponsor</code> a été rendu visible dans la vue CMS;
- les chaînes URL vides invalides de plusieurs fiches ont été nettoyées;
- quatre identifiants Instagram ont été normalisés en URL HTTPS;
- deux libellés Facebook historiques restent à corriger faute d'URL certaine;
- Android 27 a été publié en test interne;
- iOS 27 a été accepté au téléversement TestFlight.

Les opérations ci-dessus ne prouvent pas un état identique en production.

## 12. Incidents résolus et leçon à conserver

| Incident | Résolution |
| --- | --- |
| avis HTTP 400 avec anciens chemins | compatibilité des IDs et chemins dans <code>636ba99</code> |
| signature Stripe invalide | rotation du secret d'environnement; Stripe reste Web/legacy |
| OIDC Google 401 générique | diagnostics sûrs sans fuite dans <code>6dbe846</code> |
| échec de récupération des certificats Google dans Wix | chargeur <code>wix-fetch</code> borné et cache single-flight dans <code>5da0709</code> |
| anciens messages RTDN synthétiques en boucle | snapshot récupérable puis seek ciblé; aucun relâchement de validation |
| thème Android dépendant d'un paquet retiré | restauration des thèmes Flutter natifs |
| migration SwiftPM bloquant la CI | collecte sur macOS, allowlist et intégration contrôlée |
| certificat Android auto-signé rejeté par la CI | validation de chaîne et d'empreinte adaptée |
| fichiers générés divergents | synchronisation explicite et garde Git conservée |
| Instagram/WhatsApp non reconnaissables | Font Awesome et couleurs de marque |
| Premium considéré à tort comme vedette | source de vérité <code>sponsor</code> |
| workflow iOS rouge après upload réussi | <code>fi</code> manquant ajouté au nettoyage |

## 13. Dette et travail restant

### Bloquants avant production

1. Intégrer <code>fix/store-release-1.1.0-28</code> dans <code>main</code> par PR
   revue, sans inclure la PR Dependabot #11 sans rapport.
2. Rejouer la CI complète sur le commit de fusion exact et verrouiller
   <code>MOBILE_PRODUCTION_APPROVED_SHA</code> sur ce SHA avant les builds.
3. Lancer <code>Android Release</code> avec <code>upload_internal=true</code> et
   <code>iOS Release</code> avec <code>upload_testflight=true</code>, puis prouver
   1.1.0 (28) dans la piste interne et TestFlight sans promotion publique.
4. Tester les deux produits du store sur Android et iOS : achat, pending, annulation,
   erreur, restauration, renouvellement, expiration, remboursement/révocation
   et changement de formule.
5. Prouver au moins une vraie <code>subscriptionNotification</code> Google
   relue par l'API; le testNotification ne suffit pas.
6. Configurer et tester App Store Server Notifications V2.
7. Vérifier dans App Store Connect l'existence, l'activation, la localisation
   et les contrats des deux abonnements. Aucun état Apple complet n'est prouvé
   par Git.
8. Revalider la banque, la fiscalité, App Privacy, Google Data Safety, la
   politique de confidentialité, les conditions et le support.
9. Conserver les preuves de la promotion Wix production du 5 octobre 2026 et
   revalider schémas, index, permissions, secrets et sauvegardes avant chaque
   évolution ultérieure.
10. Ajouter une réconciliation périodique Apple/Google pour réparer un droit si
    toutes les notifications ont été manquées.
11. Mettre une protection edge/CDN devant les écritures publiques sensibles.
12. Définir surveillance, alertes, support et retour arrière.

### Dette de données et contenu

- migrer <code>Reviews.isApproved</code> vers un vrai booléen;
- auditer les anciennes associations d'avis avant de retirer leurs alias;
- auditer chaque fiche legacy avant de définir <code>sponsor=true</code>;
- corriger les deux libellés Facebook incomplets seulement avec une URL
  certaine;
- ne supprimer aucun champ CMS seulement parce qu'il est masqué dans une vue;
- le logo mobile du site Wix a été observé rogné dans une émulation réelle et
  reste à ajuster visuellement.

### Dette de documentation

- [PRODUCTION_EVIDENCE_2026-09-22.md](../PRODUCTION_EVIDENCE_2026-09-22.md)
  est un registre historique, pas l'état courant;
- les nombres de tests dans les anciens guides sont datés;
- l'inventaire de confidentialité détaillé existe dans une branche séparée et
  doit être revu avant intégration;
- toute nouvelle preuve de store doit être ajoutée ici avec date, commit et
  lien.

## 14. Tests et commandes

Contrôles locaux canoniques :

    flutter pub get --enforce-lockfile
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze --fatal-infos --fatal-warnings
    flutter test --coverage --reporter expanded
    npm test --prefix backend
    git diff --check

Contrôles ciblés utiles :

    flutter test test/services/store_purchase_service_test.dart
    flutter test test/pages/professional_registration_page_test.dart
    flutter test test/pages/professionnel_detail_responsive_test.dart
    node backend/test/store-purchase-core.test.js
    node backend/test/store-notifications.test.js
    node backend/test/store-purchase-verifiers.test.js

Aucun dossier <code>integration_test/</code> n'existe. Les achats réels, les
stores, les notifications et Wix restent donc des validations d'intégration
manuelles et externes.

## 15. Procédure de reprise pour une nouvelle IA

1. Lire [AGENTS.md](../AGENTS.md) et ce document.
2. Lancer <code>git status --short --branch</code>.
3. Mettre à jour les références distantes sans modifier le travail local.
4. Comparer <code>origin/main</code>, la branche courante et leur merge-base.
5. Lire le guide spécialisé avant de toucher au paiement, à Wix ou aux stores.
6. Pour un défaut, reproduire et ajouter un test avant le correctif.
7. Pour une opération externe, capturer : service, environnement, commit,
   version/build, résultat et lien/preuve.
8. Ne jamais demander ou recopier une valeur secrète dans le chat.
9. Ne jamais promettre une publication ou un revenu; distinguer objectif,
   hypothèse et mesure.
10. Mettre à jour ce document après chaque lot significatif.

## 16. Où chercher selon le problème

| Problème | Fichiers de départ |
| --- | --- |
| application ne démarre pas | <code>lib/main.dart</code>, bootstrap, AppConfig |
| professionnels absents | DataService, <code>get_professionals</code>, <code>toPublicProfessional</code>, CMS <code>isActive/sponsor</code> |
| avis absent | AddReviewPage, DataService, <code>post_review/get_reviews</code>, modération Wix |
| prix indisponible | IDs produits, <code>queryProducts</code>, statut des produits dans le store |
| achat non confirmé | StorePurchaseService, create/confirmStorePurchase, verifiers, Entitlements |
| restauration | <code>restoreStorePurchase</code> client et serveur |
| renouvellement/révocation | notification core/service et webhooks Apple/Google |
| RTDN 401/503 | secrets OIDC, audience, e-mail, certificats Google, Wix Logs |
| fiche payée non publiée | comportement normal : vérifier modération, pas le paiement |
| mise en vedette incorrecte | <code>Professionnel.sponsor</code>, droit et plan professional |
| problème de signature | workflow staging/release, profil/certificat ou keystore |
| problème de confidentialité | [SECURITY.md](../SECURITY.md) et inventaire à intégrer |

## 17. Documents de référence

- [README.md](../README.md) — vue produit et architecture;
- [SECURITY.md](../SECURITY.md) — modèle de confiance;
- [TESTING.md](../TESTING.md) — stratégie de validation;
- [RELEASE.md](../RELEASE.md) — release Android/iOS;
- [WIX_DEPLOYMENT.md](../WIX_DEPLOYMENT.md) — collections, secrets et déploiement;
- [production_checklist.md](../production_checklist.md) — gates opérationnelles;
- [GOOGLE_PLAY_INFO.md](../GOOGLE_PLAY_INFO.md) — fiche et configuration Play.

## 18. Règle de maintenance de ce dossier

Après chaque changement significatif, ajouter ou corriger :

- la date et le commit;
- ce qui a changé;
- les environnements touchés;
- les tests et preuves;
- les migrations de données;
- les risques et actions restantes.

Ne jamais écrire « terminé », « production » ou « sécurisé » sans préciser
l'environnement et la preuve exacte.
