# Politique de sécurité

## Signaler une vulnérabilité

N'ouvrez pas de billet public pour une vulnérabilité exploitable ou une fuite
de données. Utilisez le formulaire privé **Report a vulnerability** dans
l'onglet Security du dépôt GitHub et indiquez :

- la version, la plateforme et l'environnement concernés;
- les étapes de reproduction minimales;
- l'impact observé ou plausible;
- une piste de correction, si elle est connue.

Ne joignez jamais de secret, de donnée personnelle réelle ni de capture qui en
contient. Attendez une confirmation de réception avant toute divulgation
publique coordonnée.

## Périmètre prioritaire

Les signalements sur Stripe, les fonctions Wix, les permissions de
collections, le Media Manager, l'inscription professionnelle, la modération et
l'exposition de renseignements personnels sont prioritaires.

## Modèle de confiance

- Le client Flutter et tous ses champs sont non fiables.
- Toutes les collections Wix doivent être privées. Seul le backend Velo lit ou
  écrit avec ses privilèges serveur.
- Les endpoints publics renvoient des projections par liste blanche. Ajouter un
  champ dans Wix ne doit jamais l'exposer automatiquement.
- Le répertoire ne publie que les professionnels actifs. Un avis doit avoir
  `isApproved=true` ou `moderationStatus=approved`.
- Toute inscription, gratuite ou payante, crée un professionnel inactif avec
  le statut `pending_review`. Un paiement réussi confirme seulement le volet
  financier : il ne doit jamais activer ni publier automatiquement le contenu.
- Le catalogue serveur est la source de vérité des forfaits, prix, devises et
  capacités. Les montants envoyés par le client ne sont que des indices à
  comparer, jamais une autorité.
- Les confirmations Stripe revalident le statut, le montant, la devise et les
  métadonnées liées au checkout. Les jetons gratuits sont signés, liés au
  checkout et expirent.
- Les identifiants déterministes rendent les confirmations et le webhook
  idempotents; un second appel ne doit pas créer un second profil.

Les projections publiques incluent actuellement certaines coordonnées
professionnelles (courriel, téléphone, adresse et liens sociaux). Elles doivent
donc être considérées comme publiques dans les consentements et la politique de
confidentialité. Les champs de paiement, empreintes et identifiants Stripe ne
font pas partie de la projection publique.

## Images et Media Manager

Les images arrivent temporairement dans la requête sous forme de data URL
Base64, puis le backend :

1. borne la taille et le nombre d'images;
2. vérifie la signature binaire PNG, JPEG ou WebP;
3. calcule les empreintes utilisées pour l'intégrité et l'idempotence;
4. envoie les octets au Wix Media Manager;
5. valide le `fileUrl` retourné;
6. persiste uniquement les URL Wix et le manifeste d'empreintes.

## Mesure ROI first-party

La route `POST /_functions/engagementEvent` est publique parce qu'elle est
appelée par les clients Web et mobiles, mais son contrat est fermé :

- aucune chaîne libre, recherche brute, coordonnée, URL, adresse ou identité
  d'utilisateur n'est acceptée;
- le UUID aléatoire sert uniquement à l'idempotence, puis seul son dérivé
  haché devient l'identifiant Wix;
- la catégorie n'est pas acceptée depuis le client : aucun champ libre ne peut
  servir à dissimuler une donnée personnelle;
- les événements liés à une fiche exigent un professionnel actif;
- la taille, les enums et les combinaisons de champs sont validés avant toute
  écriture;
- le rapport est un Web Method `Permissions.Admin` et ne renvoie aucun
  événement brut;
- la collection `EngagementEvents` reste privée et une tâche supprime les
  événements de plus de 400 jours ainsi que les limiteurs API expirés.

Le client utilise une file mémoire bornée à 100 événements et conserve le même
UUID lors d'au plus deux reprises transitoires; les erreurs 4xx ne sont pas
rejouées. Cette file protège l'expérience et l'idempotence, mais elle n'est pas
une preuve de livraison ni un historique persistant : une fermeture brutale
peut perdre les derniers événements. Une outbox locale persistante reste une
amélioration v2.

Le limiteur applicatif réduit le bruit automatisé sans constituer une preuve
d'attribution financière. Les rapports doivent parler d'« interactions dans
l'application », jamais de visiteurs uniques ou de ventes garanties. Jusqu'à
l'installation d'une protection edge/CDN ou d'une attestation d'application,
chaque événement porte `client_reported_unverified` et reste exclu de toute
facturation ou garantie de résultat.

Aucune chaîne `data:image/...;base64` ne doit être enregistrée dans
`PaymentCheckouts` ou `Professionnel`. En cas d'échec, le backend tente un
nettoyage compensatoire des fichiers nouvellement envoyés, sans toucher aux URL
déjà référencées. Ce nettoyage est une mesure de réduction du risque, pas une
transaction atomique : surveillez les erreurs `checkout_media_cleanup` et
prévoyez une tâche de réconciliation des orphelins.

## Secrets et historique Git

Les secrets `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` et
`CHECKOUT_SIGNING_SECRET` appartiennent exclusivement au gestionnaire de
secrets Wix. La clé Stripe publiable est la seule clé Stripe attendue dans le
binaire, injectée au build.

Une ancienne valeur `WIX_API_KEY` a potentiellement figuré dans le fichier
historique `.env.production`. Sa suppression du répertoire de travail ne la
révoque pas et ne l'efface pas de l'historique Git. Si cette valeur était
réelle :

1. la révoquer dans Wix;
2. créer une nouvelle clé avec les privilèges minimaux;
3. mettre à jour uniquement le coffre concerné;
4. analyser tout l'historique avec un outil tel que Gitleaks;
5. coordonner un nettoyage d'historique si nécessaire, puis demander aux
   collaborateurs de resynchroniser leurs clones.

Appliquez la même procédure à toute clé Stripe ou Firebase réelle qui aurait
été exposée. Ne copiez jamais une valeur de production dans un ticket, un
journal ou une capture d'écran.

## Limites connues

- Le rate limiting Wix repose sur une séquence lecture/mise à jour non atomique;
  ajoutez un contrôle CDN/WAF pour les pics importants.
- Les parcours principaux utilisent les routes v2 `/categories`,
  `/professionals`, `/reviews`, `/partners` et `/offers`, avec une taille de
  page bornée, un curseur opaque lié aux filtres et des projections publiques.
  Les index Wix et le comportement sous charge doivent encore être validés sur
  l'environnement réellement déployé.
- `GET /data` agrège toujours plusieurs collections en mémoire pour les anciens
  clients. Ses plafonds empêchent une croissance incontrôlée, mais cette route
  v1 doit rester mesurée, sans nouveau consommateur, puis être retirée lorsque
  son usage est nul.
- Les forfaits payants ne sont pas pris en charge sur Web.
- Les tests automatisés ne prouvent pas la configuration réelle des permissions
  Wix, des secrets, du webhook ou du Media Manager.

## Versions prises en charge

Seule la dernière version publiée est prise en charge. Un secret compromis doit
être révoqué immédiatement, indépendamment du calendrier de publication.

La procédure technique de mise en production est dans
[WIX_DEPLOYMENT.md](WIX_DEPLOYMENT.md).
