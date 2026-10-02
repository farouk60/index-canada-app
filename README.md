# Index Canada

Index Canada est une application Flutter bilingue (français/anglais) qui
permet de découvrir des professionnels, services, partenaires et offres au
Canada. Wix fournit le CMS et le backend privé; Stripe traite les paiements sur
le Web ou les parcours backend historiques qui sont encore activés. Sur iOS et
Android, le forfait Basique reste gratuit et les forfaits annuels payants sont
achetés exclusivement avec StoreKit ou Google Play Billing, puis validés côté
serveur avant l'attribution d'un droit.

Le dépôt a été renforcé pour rendre le code reproductible, limiter
l'exposition des données et sécuriser le parcours inscription → paiement →
publication. Cela ne constitue pas, à lui seul, une garantie de disponibilité
ou de succès commercial : la validation de bout en bout en préproduction, les
essais réels et une promotion contrôlée vers la production restent obligatoires.

## Reprise rapide du projet

Une IA ou une nouvelle personne doit commencer par :

- [AGENTS.md](AGENTS.md) pour les règles non négociables;
- [docs/AI_PROJECT_HANDOFF.md](docs/AI_PROJECT_HANDOFF.md) pour l'état daté,
  l'architecture, l'historique des changements, les preuves et le travail
  restant;
- [SECURITY.md](SECURITY.md), [TESTING.md](TESTING.md),
  [RELEASE.md](RELEASE.md) et [WIX_DEPLOYMENT.md](WIX_DEPLOYMENT.md) pour les
  procédures spécialisées.

Au 2 octobre 2026, Android 1.1.0 (27) est en test interne et iOS 1.1.0
(27) a été accepté au téléversement TestFlight. Ces builds ciblent la
préproduction Wix; aucune publication publique ni promotion Store Billing du
backend Wix production n'est prouvée.

## Architecture retenue

Wix reste une bonne solution pour ce produit tant qu'il sert de CMS et de
console d'administration, avec les règles suivantes :

- toutes les collections sont privées; l'application ne les interroge jamais
  directement;
- les fonctions Wix Velo de `backend/http-functions.js` sont l'unique porte
  d'entrée aux données;
- chaque réponse publique est reconstruite avec une liste blanche de champs;
- seuls les professionnels actifs, les contenus visibles et les avis
  explicitement approuvés sont publiés;
- les prix, capacités des forfaits, montants et activations sont décidés par le
  serveur;
- toute nouvelle inscription, gratuite ou payante, est créée avec
  `registrationStatus=pending_review` et `isActive=false`; le paiement ne vaut
  jamais approbation ni publication, qui restent des actions humaines dans Wix;
- les images validées sont envoyées au Wix Media Manager; les collections
  `PaymentCheckouts` et `Professionnel` ne conservent que les `fileUrl` Wix et
  les empreintes, jamais les données Base64;
- les lectures Wix parcourent toutes les pages jusqu'à un plafond explicite :
  `Professionnel` 10 000, `Reviews` 10 000, et 2 000 pour
  `SousCategorie`, `Partenaires` et `OffresPartenaire`.
- la mesure ROI first-party enregistre uniquement des dimensions fermées
  (impression, vue, clic, contact, copie de coupon et recherche agrégée), sans
  terme recherché, nom, courriel, téléphone, adresse, URL ni identifiant
  d'utilisateur/appareil;
- les événements ROI sont idempotents, limités par IP hachée, conservés environ
  13 mois et projetés dans un rapport accessible uniquement aux administrateurs
  Wix;
- le client les place dans une file mémoire bornée à 100 événements et rejoue
  au plus deux fois uniquement les échecs transitoires avec le même identifiant
  idempotent; les erreurs 4xx ne sont pas rejouées et le parcours utilisateur
  n'est jamais bloqué. Cette file n'est pas persistante : une fermeture brutale
  peut perdre les derniers événements.

Les parcours principaux du client utilisent maintenant les endpoints v2
`GET /categories`, `/professionals`, `/reviews`, `/partners` et `/offers`.
Chaque ressource est filtrée côté serveur et paginée avec `limit` et un
`cursor` opaque lié aux filtres de la requête. `GET /data` continue d'agréger
le répertoire complet uniquement pour la compatibilité v1; aucun nouveau
parcours ne doit en dépendre et son retrait doit être piloté par la mesure de
son usage.

`GET /professionals` accepte `category`, `search`, `city`, `featured` et
`ids`; `GET /reviews` exige `professionalId`. Une page contient 25 éléments
par défaut et au plus 100. Le client courant demande des pages de 100 et suit
`pagination.next_cursor` jusqu'à `has_more=false`.

## Principes du projet

- Expérience français/anglais, navigation adaptative et préférence de langue
  persistée.
- Accessibilité native : mise à l'échelle du texte, zones tactiles suffisantes
  et libellés sémantiques.
- Configuration publique injectée au build, sans secret dans l'application.
- Forfait Basique gratuit, sans achat auprès d'un store. Les forfaits Premium
  et En Vedette sont des abonnements annuels renouvelables achetés avec
  StoreKit sur iOS et Google Play Billing sur Android; leur prix affiché vient
  toujours du store de l'utilisateur.
- Aucun SDK, clé publiable ou secret Stripe n'est embarqué dans le client
  mobile. Stripe demeure limité à un éventuel parcours Web/legacy séparé.
- Un achat mobile n'active jamais directement un profil : le backend vérifie la
  transaction auprès d'Apple ou Google, gère le droit et maintient la fiche en
  modération jusqu'à son approbation dans Wix.
- Tests déterministes sans accès à Apple, Google Play, Stripe, Firebase ou Wix
  en production.

## Démarrage local

Prérequis : Flutter `3.47.4`, Dart `3.13.3`, JDK `17` et les SDK natifs de la
plateforme ciblée. La chaîne Android utilise Gradle `8.14.5`, Android Gradle
Plugin `8.11.1` et Kotlin Gradle Plugin `2.2.21`.

```bash
flutter pub get --enforce-lockfile
flutter run \
  --dart-define=APP_ENVIRONMENT=development \
  --dart-define=API_BASE_URL=https://votre-domaine/_functions
```

Le fichier `.env.example` documente les valeurs disponibles; Flutter ne le lit
pas automatiquement. Ne commettez jamais de fichier `.env` réel.

La configuration est validée au démarrage. En `production`, `API_BASE_URL` doit
être une URL HTTPS réelle et non une valeur d'exemple. Les identifiants publics
des produits annuels sont versionnés par l'application, mais aucun secret
Apple, Google Play ou Stripe ne doit être transmis au client, dans un fichier
`.env` ou par `--dart-define`. Les justificatifs d'achat sont envoyés au backend
pour vérification; les identifiants de service et certificats restent dans le
gestionnaire de secrets Wix.

## Backend Wix, Store Billing et compatibilité Stripe

Pour les achats mobiles, le gestionnaire de secrets Wix doit contenir les
valeurs propres à l'environnement documentées dans
[WIX_DEPLOYMENT.md](WIX_DEPLOYMENT.md), notamment :

- `CHECKOUT_SIGNING_SECRET` : valeur aléatoire d'au moins 32 octets pour les
  confirmations et les empreintes anti-abus;
- `CHECKOUT_SIGNING_SECRET_PREVIOUS` : anciennes valeurs encore acceptées
  pendant une rotation contrôlée;
- `APPLE_APP_ID` et les trois secrets `APPLE_ROOT_CERTIFICATE_G1_BASE64`,
  `APPLE_ROOT_CERTIFICATE_G2_BASE64` et `APPLE_ROOT_CERTIFICATE_G3_BASE64`
  pour les certificats racine Apple officiels, séparés afin que chaque valeur
  respecte la limite de taille d'un secret Wix;
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` et les paramètres `GOOGLE_RTDN_*` pour la
  validation Google Play et les notifications temps réel;
- `STORE_ALLOW_SANDBOX=true` uniquement en préproduction.

`STRIPE_SECRET_KEY` et `STRIPE_WEBHOOK_SECRET` ne sont requis que si le parcours
Web/legacy Stripe correspondant reste déployé. Ils ne servent jamais à un
achat natif iOS ou Android et ne doivent jamais être copiés dans l'application.

Les collections de contenu et les collections techniques
`PaymentCheckouts`, `Entitlements`, `PaymentEvents`, `ApiRateLimits` et
`EngagementEvents` doivent être privées. Le backend valide les transactions
auprès d'Apple ou Google, traite les renouvellements, restaurations,
changements de formule, expirations et révocations, puis applique ces événements
de manière idempotente. Aucun reçu, jeton d'achat brut ou secret de service ne
doit être persisté ou journalisé. Si la compatibilité Stripe Web/legacy est
conservée, son webhook `POST /_functions/stripeWebhook` et sa vérification de
signature restent un flux séparé.

Le limiteur persiste ses compteurs dans Wix. Il échoue en mode fermé pour les
écritures sensibles, mais une séquence lecture/mise à jour Wix n'est pas un
incrément atomique sous forte concurrence. Ajoutez une limite CDN/WAF avant un
lancement à fort trafic.

`POST /_functions/engagementEvent` accepte uniquement le contrat ROI v1. Le
UUID d'idempotence est haché et n'est pas conservé en clair. Le rapport agrégé
est exposé par un Web Method `Permissions.Admin`, jamais par une route publique.
Les événements anonymes sont explicitement marqués non vérifiés et ne doivent
pas servir à facturer un professionnel ni à garantir une vente.

La procédure complète, les permissions, les vérifications Media Manager et le
retour arrière sont décrits dans [WIX_DEPLOYMENT.md](WIX_DEPLOYMENT.md).

## Qualité

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage --reporter expanded
npm test --prefix backend
```

La CI contrôle les secrets, le backend, le format, l'analyse et les tests, puis
compile les plateformes prévues. Le commit fonctionnel `07e2197` a un
[passage Flutter CI vert](https://github.com/farouk60/index-canada-app/actions/runs/37016569680)
et une [validation iOS staging verte](https://github.com/farouk60/index-canada-app/actions/runs/37019413309).
Ces preuves automatisées ne remplacent ni les achats réels, ni les tests sur
appareils, ni une décision de production. Consultez [TESTING.md](TESTING.md).

## Structure utile

- `lib/core/` : configuration, démarrage, erreurs et journalisation;
- `lib/pages/` et `lib/widgets/` : écrans et composants adaptatifs;
- `lib/services/` : contrats réseau, paiement et services externes;
- `backend/http-functions.js` : endpoints Wix et orchestration serveur;
- `backend/security-core.js` : validation, projections, intégrité et médias;
- `backend/directory-pagination.js` : lecture complète bornée des collections;
- `backend/engagement-report.js` : agrégation déterministe des interactions;
- `backend/engagement-report.web.js` : rapport privé réservé aux administrateurs;
- `backend/engagement-maintenance.js` : purge de rétention planifiée;
- `test/` et `backend/test/` : tests Flutter et backend.

## Règles avant publication

1. Déployer d'abord dans un environnement Wix isolé, avec le sandbox Apple et
   les testeurs sous licence Google Play; `STORE_ALLOW_SANDBOX` doit rester
   désactivé en production.
2. Exécuter les parcours recherche, avis, inscription Basique gratuite, achats
   annuels StoreKit/Google Play, restauration, changement de forfait,
   notifications store, reprise idempotente et modération.
3. Confirmer que toute inscription, gratuite ou payante, reste
   `pending_review` et inactive jusqu'à validation humaine dans Wix.
4. Valider la politique de confidentialité bilingue et le consentement pour les
   coordonnées destinées à être publiques.
5. Configurer la signature Android (`android/key.properties`) et la signature
   iOS. Le contournement `-PindexCanada.allowUnsignedRelease=true` est réservé
   à la CI et produit un artefact non distribuable.
6. Configurer les produits annuels, les notifications App Store Server et
   Google RTDN, puis vérifier renouvellement, annulation, expiration,
   remboursement et révocation avant une soumission publique.
7. Si un paiement Web/legacy Stripe est maintenu, le tester séparément en mode
   test avec son propre webhook; ce flux ne valide pas les achats mobiles.
8. Révoquer et remplacer toute ancienne clé Wix réelle qui aurait figuré dans
   `.env.production` ou l'historique Git; supprimer le fichier courant ne
   révoque pas la clé et ne nettoie pas l'historique.

Voir aussi [SECURITY.md](SECURITY.md) avant toute mise en production.
