# Déploiement Wix et Stripe

Ce guide décrit le déploiement du backend d'Index Canada. Il ne remplace pas
une sauvegarde, une revue de permissions ni une validation de préproduction.

## 1. Séparer les environnements

Utiliser au minimum un environnement de préproduction isolé de la production :

- collections et médias de test distincts;
- clés Stripe de test uniquement;
- secret de webhook propre à l'endpoint de préproduction;
- `CHECKOUT_SIGNING_SECRET` différent de la production;
- `API_BASE_URL` et clé Stripe publiable injectés au build correspondant.

Ne copiez pas de données personnelles de production en préproduction.

## 2. Créer et verrouiller les collections

Toutes les collections suivantes doivent refuser la lecture et l'écriture
directes par les visiteurs et membres :

- `Professionnel`;
- `SousCategorie`;
- `Reviews`;
- `Partenaires`;
- `OffresPartenaire`;
- `PaymentCheckouts`;
- `EngagementEvents`;
- `ApiRateLimits`.

Le backend accède aux collections avec ses privilèges serveur. N'assouplissez
pas les permissions pour contourner une erreur de déploiement.

Les collections de contenu restent administrables dans Wix. Les champs
techniques suivants sont essentiels :

- `Reviews` : `professionalId`, `rating`, `message`, `moderationStatus`,
  `isApproved` et dates;
- `PaymentCheckouts` : `_id`, version, statut, forfait, montant/devise,
  inscription normalisée, `images` (URL Wix uniquement), `imageHashes`,
  empreinte, identifiants Stripe/professionnel, tentatives et dates;
- `ApiRateLimits` : `_id`, `scope`, `keyHash`, `count`, `limit`, début de
  fenêtre et `expiresAt` comme texte ISO UTC canonique indexé;
- `EngagementEvents` : `_id`, `version`, `type`, `professionalId`,
  `placement`, `channel`, `resultsBucket`, `searchKind`, `locale`,
  `trustLevel`, `contentHash`, `receivedAt` et dates système Wix. Le `eventId`
  client ne doit jamais être conservé en clair. `trustLevel` est toujours fixé
  par le serveur à `client_reported_unverified`;
- `Professionnel` : statut d'inscription, activation, référence checkout,
  coordonnées publiques consenties, `image` et galerie sous forme d'URL Wix.

Les noms et types doivent correspondre au code avant l'import de données.
Faire un export de sauvegarde des collections existantes avant toute migration.

## 3. Configurer le Media Manager

Le backend importe `mediaManager` depuis `wix-media-backend` et envoie les
fichiers dans un chemin déterministe de la forme :

```text
/index-canada/professionals/<professionalId>/
```

L'identité d'exécution du backend doit pouvoir :

- téléverser une image;
- obtenir le `fileUrl` du fichier créé;
- envoyer à la corbeille un média orphelin lors du nettoyage compensatoire.

Le backend accepte seulement PNG, JPEG et WebP dans les limites du forfait et
du budget total. Il calcule les empreintes sur les octets, utilise des noms de
fichiers déterministes, valide le `fileUrl`, puis enregistre l'URL et le
manifeste d'empreintes. Il ne faut ajouter aucun champ persistant contenant les
data URL Base64 originales.

Après un essai, rechercher `data:image/` dans les enregistrements
`PaymentCheckouts` et `Professionnel` : le résultat doit être vide. Vérifier
aussi la présence des fichiers dans Media Manager et l'affichage depuis le
client.

En cas de concurrence, les URL déjà référencées sont protégées du nettoyage.
Si la persistance a un résultat incertain, le code conserve prudemment le média
plutôt que de casser un checkout potentiellement créé. Surveiller les journaux
`checkout_media_upload` et `checkout_media_cleanup`, puis réconcilier les
orphelins hors du chemin utilisateur.

## 4. Configurer les secrets Wix

Ajouter dans le gestionnaire de secrets, sans les placer dans le code :

| Secret | Valeur attendue |
|---|---|
| `STRIPE_SECRET_KEY` | Clé secrète Stripe de l'environnement |
| `STRIPE_WEBHOOK_SECRET` | Secret `whsec_...` de l'endpoint configuré |
| `CHECKOUT_SIGNING_SECRET` | Valeur aléatoire d'au moins 32 octets, propre à l'environnement |

Après rotation, redéployer ou redémarrer le backend afin que les valeurs
mises en cache en mémoire ne restent pas actives dans une instance chaude.

Si l'ancienne clé Wix potentiellement présente dans `.env.production` était
réelle, la révoquer avant ce déploiement. Nettoyer un fichier local ne suffit
pas; analyser également l'historique Git.

## 5. Installer Stripe et déployer le backend

Le fichier `backend/http-functions.js` importe le SDK serveur `stripe`. Avant
de publier le site Wix :

1. ouvrir **Code > Packages & Apps > npm** dans Wix;
2. rechercher `stripe` et installer exactement la version **`22.6.2`**;
3. vérifier que la version affichée par Wix correspond à celle fixée dans
   `backend/package.json` et `backend/package-lock.json`;
4. valider l'import et un paiement de test dans l'environnement de
   préproduction avant toute promotion.

`npm ci --prefix backend` installe la même version pour les contrôles locaux et
la CI, mais n'installe pas le paquet dans le site Wix. Ne remplacez pas la
version exacte par `latest` ou une plage flottante. Si Wix ne propose pas cette
version, ou si son environnement Node refuse le paquet, le déploiement reste
**NO-GO** jusqu'à une version explicitement choisie, verrouillée, testée et
reportée dans les deux manifestes et dans ce guide.

La version `22.6.2` a été vérifiée dans le
[registre npm officiel](https://registry.npmjs.org/stripe/latest) le
18 septembre 2026. Le SDK requiert Node.js 18 ou supérieur et ne contient pas
de dépendance native; sa compatibilité avec l'environnement Wix réellement
utilisé doit néanmoins être prouvée en préproduction. Wix documente également
les [contraintes de compatibilité des paquets npm](https://dev.wix.com/docs/develop-websites/articles/coding-with-velo/packages/about-npm-packages).

Déployer ensemble :

- `backend/http-functions.js`;
- `backend/security-core.js`;
- `backend/directory-pagination.js`;
- `backend/engagement-report.js`;
- `backend/engagement-report.web.js`;
- `backend/engagement-maintenance.js`;
- `backend/jobs.config`.

Si le site possède déjà un `jobs.config`, fusionner les tâches
`purgeExpiredEngagementEvents` et `purgeExpiredApiRateLimits` au lieu de
remplacer les tâches existantes. Elles s'exécutent séparément chaque jour : la
première conserve environ 13 mois d'événements bruts, la seconde supprime les
limiteurs expirés. Chacune des deux tâches traite au maximum 25 000 éléments
par exécution quotidienne; `hasMore` rend le résultat non sain et doit
déclencher une surveillance. Une modification de tâche planifiée ne prend effet
qu'après publication du site.

Les routes attendues sont :

| Méthode | Route | Usage |
|---|---|---|
| `GET` | `/_functions/data` | Répertoire agrégé compatible v1 |
| `GET` | `/_functions/searchProfessionals` | Recherche bornée |
| `GET` | `/_functions/categories` | Catégories v2, `limit` et `cursor` |
| `GET` | `/_functions/professionals` | Professionnels v2; `category`, `search`, `city`, `featured`, `ids`, `limit`, `cursor` |
| `GET` | `/_functions/reviews` | Avis approuvés v2; `professionalId` obligatoire, `limit`, `cursor` |
| `GET` | `/_functions/partners` | Partenaires actifs et officiels v2, `limit`, `cursor` |
| `GET` | `/_functions/offers` | Offres actives v2, `limit`, `cursor` |
| `GET` | `/_functions/paymentPlans` | Catalogue public projeté |
| `POST` | `/_functions/review` | Avis créé en attente de modération |
| `POST` | `/_functions/engagementEvent` | Interaction ROI anonyme et idempotente |
| `POST` | `/_functions/createPaymentIntent` | Checkout idempotent et upload des médias |
| `POST` | `/_functions/confirmPayment` | Confirmation gratuite signée ou Stripe |
| `POST` | `/_functions/stripeWebhook` | Finalisation Stripe signée |

Les routes `POST` doivent répondre `no-store`; les routes de lecture peuvent
être mises en cache selon les en-têtes du code. Restreindre les origines CORS
au domaine Web réel avant d'activer un futur paiement Web. Les applications
natives ne doivent pas dépendre d'un contournement de permissions de collection.
Les nouvelles tentatives clientes de mesure ROI doivent réutiliser le même
`eventId`; la file locale est bornée à 100 événements et ne rejoue pas les
erreurs 4xx.

Le rapport ROI n'est pas une route HTTP publique. La méthode
`getEngagementReport` du module Web exige `Permissions.Admin` et retourne
uniquement des agrégats. Elle décrit des interactions dans l'application, pas
des visiteurs uniques ni des ventes attribuées. Elle refuse une période qui
dépasse 10 000 événements et exige alors une période plus courte.

## 6. Configurer Stripe

1. Créer un endpoint vers
   `https://<domaine-wix>/_functions/stripeWebhook`.
2. Activer au minimum `payment_intent.succeeded`.
3. Copier le secret de signature de cet endpoint dans
   `STRIPE_WEBHOOK_SECRET`.
4. Vérifier que `STRIPE_SECRET_KEY` et la clé publiable du binaire appartiennent
   au même mode (test ou production) et au même compte.
5. Effectuer un paiement de test et confirmer une réponse HTTP 2xx du webhook.
6. Rejouer le même événement : aucun second profil ni second paiement ne doit
   apparaître.

Le serveur recalcule le prix depuis son catalogue et lie l'intention au
checkout par ses métadonnées. Ne créez jamais un prix ou une activation à partir
d'un montant fourni uniquement par le client.

## 7. Valider les données publiques

Le backend ne sérialise pas les documents Wix complets; il applique les
fonctions `toPublic*` de `backend/security-core.js`. Avant publication :

- inspecter un exemple de chaque réponse;
- confirmer l'absence de `paymentId`, `checkoutId`, empreintes, données de
  limitation et champs internes;
- confirmer que les coordonnées professionnelles exposées sont prévues par le
  produit et consenties;
- soumettre un avis non modéré et confirmer qu'il est absent de `GET /data`;
- désactiver un professionnel/partenaire/offre et confirmer sa disparition.

Tout nouveau champ CMS est privé par défaut. Il doit être ajouté explicitement
à une projection seulement après revue de confidentialité.

## 8. Vérifier la pagination, les index et la capacité

Les cinq routes v2 sont le contrat principal du client. Elles renvoient
`version: 2`, la liste demandée et :

```json
{
  "pagination": {
    "limit": 100,
    "has_more": true,
    "next_cursor": "curseur-opaque"
  }
}
```

`limit` vaut 25 par défaut et doit rester compris entre 1 et 100. Le curseur
est lié à la collection et aux filtres : ne jamais le construire, le modifier
ou le réutiliser avec une autre requête. La pagination est ordonnée par `_id`;
une page contenant uniquement des éléments masqués doit tout de même faire
progresser le curseur sans boucle ni doublon.

Avant la préproduction, vérifier ou créer les index Wix correspondant aux
prédicats réellement utilisés :

| Collection | Index/prédicats à valider |
|---|---|
| `Professionnel` | `isActive`; `isActive + sponsor`; catégorie canonique avec `isActive`; ordre stable par `_id` |
| `Reviews` | approbation (`isApproved` ou `moderationStatus`) + `professionalId`; ordre stable par `_id` |
| `Partenaires` | `isActive + isOfficial`; ordre stable par `_id` |
| `OffresPartenaire` | `isActive`; ordre stable par `_id` |
| `SousCategorie` | ordre stable par `_id` |
| `EngagementEvents` | `professionalId + _createdDate`; `_createdDate` pour la purge; `_id` unique pour l'idempotence |
| `ApiRateLimits` | `expiresAt` (texte ISO UTC canonique) pour la purge quotidienne; `_id` unique |

Tant que les anciens champs `sousCategorie`, `sousCatgorie`,
`professionnelId` ou `image` contiennent encore des associations, ajouter les
index équivalents réellement requis ou migrer les données vers `category` et
`professionalId`. Ne supprimer un index historique qu'après mesure des
requêtes en préproduction.

Le client doit parcourir les curseurs v2 jusqu'à `has_more=false`. La route v1
`/data` parcourt encore `hasNext()`/`next()` pour sa compatibilité et refuse un
jeu qui dépasse :

| Collection | Plafond |
|---|---:|
| `Professionnel` | 10 000 |
| `Reviews` | 10 000 |
| `SousCategorie` | 2 000 |
| `Partenaires` | 2 000 |
| `OffresPartenaire` | 2 000 |

Un plafond est un coupe-circuit, pas un objectif de capacité. Créer une alerte
bien avant 80 %. Charger en préproduction plus d'une page par ressource,
exécuter chaque combinaison de filtres v2, confirmer les index utilisés, puis
mesurer latence, erreurs 429/503, doublons, éléments manquants et stabilité des
curseurs. Conserver `/data` seulement pour les anciens clients, mesurer ses
appels, puis le retirer quand leur usage est nul.

## 9. Gate de préproduction

Ne pas promouvoir si un point échoue :

- collections privées et projections inspectées;
- cinq routes v2 testées sur plusieurs pages avec leurs filtres, index Wix et
  curseurs opaques;
- secrets présents, anciens secrets révoqués;
- 132 tests Flutter et 72 tests backend réussis au 23 septembre 2026, ou
  résultats ultérieurs équivalents consignés pour la version candidate;
- `flutter analyze` sans anomalie;
- builds CI Web, Android et iOS réellement verts;
- inscriptions gratuite et payante inactives et `pending_review` jusqu'à
  approbation humaine dans Wix;
- avis invisible avant approbation;
- aucune donnée Base64 persistée;
- paiement test, webhook, rejeu idempotent et reprise réseau validés;
- journaux sans données personnelles ni secret;
- événement ROI rejouable sans doublon, données interdites rejetées et rapport
  inaccessible à un visiteur ou membre ordinaire;
- purge de rétention testée sur une copie de données et tâche Wix publiée;
- sauvegarde et procédure de retour arrière testées.

La dernière couverture Flutter mesurée avant ROI v1 (29,6 % le 18 septembre
2026) reste une limite acceptée temporairement, pas un critère suffisant de
mise en production. Elle doit être recalculée pour toute version candidate.

## 10. Promotion et surveillance

1. Exporter les collections de production.
2. Déployer le backend compatible avec le schéma actuel.
3. Effectuer les tests de fumée avec un petit jeu de données contrôlé.
4. Publier les clients avec l'URL et la clé publiable de production.
5. Surveiller taux d'erreur, HTTP 429/503, latence, webhooks Stripe en échec,
   `CHECKOUT_PERSISTENCE_UNCERTAIN`, uploads et nettoyages de médias.
6. Comparer quotidiennement, au lancement, les checkouts finalisés, profils,
   intentions Stripe et fichiers Media Manager.

## Retour arrière

En cas d'incident :

1. suspendre les nouvelles inscriptions payantes côté client ou périmètre
   réseau;
2. ne pas supprimer les checkouts, profils ou médias avant réconciliation;
3. revenir à la dernière version backend compatible avec le schéma;
4. conserver le webhook actif si cette version peut finaliser sans danger les
   paiements déjà réussis; sinon traiter ces intentions depuis Stripe avec une
   procédure approuvée;
5. restaurer une collection seulement après avoir comparé les paiements reçus
   depuis la sauvegarde;
6. documenter les identifiants de requête et réconcilier les médias orphelins.

Un retour arrière de code ne doit jamais annuler silencieusement un paiement
déjà confirmé par Stripe.
