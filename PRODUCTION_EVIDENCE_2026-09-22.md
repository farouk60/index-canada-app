# Registre de preuves de production — 22 septembre 2026

## Verdict

- **Backend Wix et Stripe : GO production.** Le backend publié répond, le webhook
  Stripe live signé est accepté et les contrôles de sécurité courants sont verts.
- **Distribution Android et iOS : NO-GO.** Aucun artefact signé ni parcours sur
  appareil réel n'est encore prouvé. Les validations juridiques et les fiches
  des stores restent également à terminer.

Ce document ne contient aucune valeur de secret, clé privée ou donnée de carte.

## Version candidate

| Élément | Preuve |
| --- | --- |
| Application | `1.0.3+21` au commit `19f9fdf223f309080e637dcefd6bdc3bdb7235fc` |
| Branche distante | `origin/main` pointe sur ce même commit |
| CI GitHub | [Flutter CI #6](https://github.com/farouk60/index-canada-app/actions/runs/35740889950), succès en 12 min 36 s |
| Backend Wix production | `origin/main` au commit racine assaini `a18061878dd6ac5df356ca14f8aa1ad7bb882820` |
| Site public | `https://www.immigrantindex.com` |

La CI réussie comprend les trois tâches suivantes : sécurité/médias/pagination
du backend, format/analyse/tests de l'application, et compilation iOS sans
signature. Elle compile aussi le Web et un AAB Android expressément non signé.
Ces artefacts de CI ne sont pas distribuables dans les stores.

## Contrôles techniques réussis

- Suite backend exécutée localement : **45 tests sur 45 réussis**.
- Audit des dépendances backend de production : **0 vulnérabilité**.
- Aucun fichier sensible suivi dans l'arbre courant.
- Aucun motif de clé Stripe, webhook, Google, GitHub ou clé privée détecté dans
  l'arbre courant.
- Les trois modules Wix actifs correspondent bit à bit au candidat applicatif
  testé.
- `stripe` est verrouillé à la version `22.6.2` dans le manifeste, le verrou et
  l'installation Wix.
- Les identifiants Android et iOS sont tous deux `ca.indexcanada.app`.

## Preuves Wix et Stripe en production

- Les routes publiques des forfaits, catégories et recherche répondent en HTTP
  200 sur le domaine de production.
- Une requête de webhook sans signature valide est rejetée en HTTP 400.
- `PaymentCheckouts` possède les 18 champs attendus, est privée et a été remise
  à 0 élément après la validation neutre.
- `ApiRateLimits` possède les 6 champs attendus et est privée.
- `Professionnel` conserve ses 25 fiches; aucun profil n'a été publié par la
  validation du webhook.
- La destination Stripe live active est `IndexCanada-Wix-Production-v2`
  (`we_1UIXeGJeQ0XvzjbE5zf9955G`) et pointe vers
  `https://www.immigrantindex.com/_functions/stripeWebhook`.
- Elle écoute uniquement `payment_intent.succeeded` avec l'API Stripe
  `2020-08-27`.
- Un événement Stripe live signé a été renvoyé et accepté en HTTP 200. Le type
  temporaire utilisé pour ce contrôle a ensuite été retiré.
- L'ancien endpoint `/_functions/webhook` a été supprimé de Stripe.
- Aucun paiement réel n'a été déclenché pendant cette validation.

## Sécurité et dette historique

- Les anciennes clés connues ont été tournées ou révoquées. Les valeurs finales
  ne sont pas enregistrées dans ce dépôt.
- Le dépôt Wix distant de production possède un historique assaini à un commit
  racine et ne contient aucun motif de secret détecté.
- Le dépôt de l'application conserve dans son ancien historique un fichier
  `.env.production` et d'anciennes configurations Firebase. Les identifiants
  concernés sont inactifs, mais une réécriture coordonnée de l'historique reste
  une opération d'hygiène à planifier.
- Le clone Wix local conserve aussi d'anciennes références de branches contenant
  des valeurs révoquées. Leur suppression locale est destructive et doit être
  effectuée séparément après confirmation.

## Portes restant à fermer avant publication mobile

1. Publier et faire approuver la politique de confidentialité, les conditions
   d'utilisation et les déclarations Google Play/App Store.
2. Fournir la clé d'envoi Android officielle, l'accès Play Console et Play App
   Signing; ne pas créer une seconde identité de signature si une clé existe.
3. Fournir l'accès Apple Developer/App Store Connect, le certificat et le profil
   de provisionnement officiels.
4. Produire un AAB et une archive iOS signés avec l'URL API de production et la
   clé Stripe publique live injectée au build.
5. Installer depuis Google Play interne et TestFlight, puis réussir les parcours
   critiques sur un Android réel et un iPhone réel.
6. Terminer les scénarios gratuits, refusés, annulés, 3-D Secure, réseau lent ou
   interrompu, médias et reprise après erreur.
7. Valider alertes, support, sauvegarde/restauration et retour arrière avant la
   décision GO mobile datée.
