# Instructions pour les agents IA

Ce fichier s'applique à tout le dépôt Index Canada. La langue de travail et de
documentation est le français. L'interface utilisateur reste bilingue FR/EN.

## Ordre de lecture obligatoire

1. Lire [docs/AI_PROJECT_HANDOFF.md](docs/AI_PROJECT_HANDOFF.md).
2. Lire [README.md](README.md), puis le guide spécialisé correspondant à la
   tâche : [SECURITY.md](SECURITY.md), [TESTING.md](TESTING.md),
   [RELEASE.md](RELEASE.md) ou [WIX_DEPLOYMENT.md](WIX_DEPLOYMENT.md).
3. Vérifier l'état réel avec <code>git status --short --branch</code>,
   <code>git log -10 --oneline</code> et les fichiers concernés. Ne jamais
   déduire l'état d'un store, de Wix ou d'un secret à partir de Git seul.

## Invariants produit

- Le client est Flutter; le backend et le CMS sont Wix Velo.
- Toutes les collections Wix restent privées. Les fonctions de
  <code>backend/http-functions.js</code> sont l'unique API publique.
- Basique est gratuit. Premium et En Vedette sont des abonnements annuels
  StoreKit/Google Play Billing sur mobile.
- Stripe est réservé au Web/legacy. Il est interdit dans le binaire mobile.
- Un paiement accorde un droit financier, jamais une publication automatique.
  Toute nouvelle fiche reste <code>pending_review</code> et inactive jusqu'à
  l'approbation humaine dans Wix.
- Le booléen <code>Professionnel.sponsor</code> est la source de vérité de la
  mise en vedette; Premium n'est pas sponsorisé.
- Un avis est créé en attente. Il n'est public qu'après modération explicite.
- Les prix mobiles affichés viennent du store. Le client ne décide ni du prix,
  ni des capacités, ni de l'état d'un droit.

## Sécurité

- Ne jamais afficher, copier dans un message, documenter ou committer une
  valeur de secret, clé privée, certificat privé, reçu ou jeton d'achat.
- Les documents peuvent citer les noms de secrets, jamais leurs valeurs.
- Ne jamais persister ou journaliser un JWS Apple, un purchase token Google ou
  un linked purchase token brut.
- Préserver les listes blanches de projection, l'idempotence, les limites de
  taille et les erreurs publiques génériques avec requestId.
- Ne pas supprimer un champ CMS historique sans export, migration coordonnée,
  retrait du code compatible et preuve de non-utilisation.

## Frontières de déploiement

- Android 1.1.0 (27) est distribué en test interne. L'IPA iOS 1.1.0 (27) a été
  acceptée au téléversement TestFlight, sans preuve encore de traitement,
  d'installation ou d'essai. Les deux ciblent la préproduction Wix et ne
  constituent pas une publication publique.
- Ne jamais fusionner dans main, publier Wix production, soumettre en
  production App Store/Google Play ou modifier des prix/contrats sans une
  autorisation explicite et distincte de Farouk.
- Les workflows staging exigent la branche candidate, le SHA exact approuvé et
  l'environnement GitHub <code>mobile-staging</code>.
- Avant toute promotion, prouver le commit exact, les tests, la signature,
  l'URL backend embarquée et les scénarios réels sur appareils.

## Conventions d'implémentation

- Flutter : configuration par <code>--dart-define</code>, services testables,
  erreurs stables, aucune donnée sensible dans les logs.
- Backend : modules ESM, logique pure dans les modules core, dépendances
  injectables pour les tests, mutations Wix orchestrées dans les services.
- Conserver les alias CMS historiques tant qu'une migration n'est pas terminée.
- Ajouter ou mettre à jour les tests avec toute règle métier.
- Après un changement important, mettre à jour
  [docs/AI_PROJECT_HANDOFF.md](docs/AI_PROJECT_HANDOFF.md), les guides touchés
  et le statut daté. Une affirmation « déployé » exige une preuve externe.

## Contrôles usuels

    dart format --output=none --set-exit-if-changed lib test
    flutter analyze --fatal-infos --fatal-warnings
    flutter test --coverage --reporter expanded
    npm test --prefix backend
    git diff --check

Si le SDK requis n'est pas disponible localement, ne pas inventer un résultat :
utiliser le workflow GitHub du commit exact et consigner le lien de preuve.
