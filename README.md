# Index Canada

Index Canada est une application Flutter bilingue (français/anglais) qui
permet de découvrir des professionnels, services, partenaires et offres au
Canada. Wix fournit le CMS et le backend privé; Stripe traite les paiements sur
Android et iOS.

Le dépôt a été renforcé pour rendre le code reproductible, limiter
l'exposition des données et sécuriser le parcours inscription → paiement →
publication. Cela ne constitue pas, à lui seul, une garantie de disponibilité
ou de succès commercial : un déploiement de préproduction et des essais réels
restent obligatoires.

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
- Paiement Stripe PaymentSheet sur Android et iOS. Les forfaits payants sont
  volontairement désactivés sur le Web tant qu'un parcours Stripe Web dédié
  n'est pas livré; le forfait gratuit reste disponible.
- Tests déterministes sans accès à Stripe, Firebase ou Wix en production.

## Démarrage local

Prérequis : Flutter `3.47.4`, Dart `3.13.3`, JDK `17` et les SDK natifs de la
plateforme ciblée. La chaîne Android utilise Gradle `8.14.5`, Android Gradle
Plugin `8.11.1` et Kotlin Gradle Plugin `2.2.21`.

```bash
flutter pub get --enforce-lockfile
flutter run \
  --dart-define=APP_ENVIRONMENT=development \
  --dart-define=API_BASE_URL=https://votre-domaine/_functions \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_votre_cle
```

Le fichier `.env.example` documente les valeurs disponibles; Flutter ne le lit
pas automatiquement. Ne commettez jamais de fichier `.env` réel.

La configuration est validée au démarrage. En `production`,
`API_BASE_URL` doit être une URL HTTPS réelle et non une valeur d'exemple. Sur
Android et iOS, `STRIPE_PUBLISHABLE_KEY` doit commencer par `pk_live_`; une clé
`pk_test_` est permise en préproduction seulement. Le Web n'exige pas de clé
Stripe tant que les forfaits payants y sont désactivés.

## Backend Wix et Stripe

Le gestionnaire de secrets Wix doit contenir :

- `STRIPE_SECRET_KEY` : clé Stripe secrète de l'environnement;
- `STRIPE_WEBHOOK_SECRET` : secret de signature du webhook correspondant;
- `CHECKOUT_SIGNING_SECRET` : valeur aléatoire d'au moins 32 octets pour les
  confirmations gratuites et les empreintes anti-abus.

Les collections de contenu et les collections techniques
`PaymentCheckouts`/`ApiRateLimits`/`EngagementEvents` doivent être privées. Le webhook Stripe
`POST /_functions/stripeWebhook` doit recevoir au minimum
`payment_intent.succeeded`. La confirmation est idempotente : le checkout,
l'intention Stripe et le profil final portent des identifiants et empreintes
déterministes, et le webhook revalide statut, montant, devise et métadonnées.

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

La CI est configurée pour contrôler les secrets, le format, l'analyse, les
tests, puis compiler Web, Android release non signé et iOS release sans
signature. Elle n'a pas été exécutée depuis cet environnement local : une
configuration présente n'est pas une preuve de pipeline vert. Consultez
[TESTING.md](TESTING.md) pour les résultats et limites connus.

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

1. Déployer et tester d'abord avec les clés Stripe de test et un environnement
   Wix isolé.
2. Exécuter les parcours recherche, avis, inscription gratuite, paiement,
   webhook, reprise idempotente et modération.
3. Confirmer que toute inscription, gratuite ou payante, reste
   `pending_review` et inactive jusqu'à validation humaine dans Wix.
4. Valider la politique de confidentialité bilingue et le consentement pour les
   coordonnées destinées à être publiques.
5. Configurer la signature Android (`android/key.properties`) et la signature
   iOS. Le contournement `-PindexCanada.allowUnsignedRelease=true` est réservé
   à la CI et produit un artefact non distribuable.
6. Révoquer et remplacer toute ancienne clé Wix réelle qui aurait figuré dans
   `.env.production` ou l'historique Git; supprimer le fichier courant ne
   révoque pas la clé et ne nettoie pas l'historique.

Voir aussi [SECURITY.md](SECURITY.md) avant toute mise en production.
