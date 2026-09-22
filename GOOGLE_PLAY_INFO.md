# Préparation de la fiche Google Play

## Statut : brouillon, non prêt à soumettre

Ce document décrit les valeurs vérifiées dans le dépôt et propose des textes de fiche. Les déclarations de confidentialité restent à confirmer sur la version de production réellement déployée. Le guide [`WIX_DEPLOYMENT.md`](WIX_DEPLOYMENT.md), les tests de bout en bout et la liste [`production_checklist.md`](production_checklist.md) doivent être terminés avant une publication.

## 1. Identité technique vérifiée

| Élément | Valeur actuelle |
| --- | --- |
| Nom de l'application | Index Canada |
| Package Android | `ca.indexcanada.app` |
| Version | `1.0.3` |
| Code de version | `21` |
| Firebase Analytics | Désactivé (stub) |
| Artefact Android CI | AAB non signé, vérification seulement |

Le package est déjà configuré. Ne pas suivre une ancienne instruction demandant de remplacer `com.example.mon_index_app`.

## 2. Métadonnées proposées

Les textes ci-dessous évitent de qualifier les professionnels de « certifiés » ou « qualifiés », car aucun mécanisme de vérification correspondant n'est démontré dans le dépôt. Ils doivent être relus après le test de la version candidate.

### Français (Canada)

**Nom**

Index Canada

**Description courte — maximum 80 caractères**

Consultez des professionnels, partenaires et offres au Canada

**Description complète**

Index Canada est un annuaire bilingue qui facilite la consultation de professionnels, de partenaires et d'offres.

Avec l'application, vous pouvez :

- parcourir les catégories disponibles ;
- rechercher des professionnels dans l'annuaire ;
- consulter leurs profils et leurs coordonnées publiées ;
- enregistrer des profils dans vos favoris ;
- découvrir des partenaires et des offres ;
- ouvrir un site Web, un courriel, le téléphone ou un itinéraire dans une application externe ;
- accéder au parcours d'inscription professionnelle.

Les profils et les offres visibles dépendent des contenus publiés dans l'annuaire. L'interface est disponible en français et en anglais.
Toute nouvelle inscription reste invisible pendant sa vérification. Le paiement
d'un forfait ne garantit ni l'approbation ni la publication d'un profil.

### Anglais (Canada)

**Name**

Index Canada

**Short description — maximum 80 characters**

Browse professionals, partners and offers in Canada

**Full description**

Index Canada is a bilingual directory for browsing professionals, partners and offers.

With the app, you can:

- browse available categories;
- search the professional directory;
- view published profiles and contact details;
- save profiles to your favourites;
- discover partners and offers;
- open websites, email, the phone dialler or directions in an external app;
- access the professional registration flow.

Available profiles and offers depend on the content published in the directory. The interface is available in French and English.
Every new registration remains hidden while it is reviewed. Paying for a plan
does not guarantee approval or publication of a profile.

### Catégorie et audience

- Catégorie candidate : **Entreprise**. Confirmer le choix final dans Play Console selon le positionnement réel.
- Public cible et tranche d'âge : **à déterminer dans le questionnaire Play Console**. Ne pas déclarer « tous publics » ou « 18+ » sans avoir évalué le contenu, les achats et le parcours d'inscription.
- Public enfant : ne pas cibler les enfants sans une décision produit et une revue de conformité dédiées.

## 3. Permissions Android réellement déclarées

| Permission | Usage actuel |
| --- | --- |
| `android.permission.INTERNET` | Appels du backend Wix, paiement et chargement des médias. |
| `android.permission.ACCESS_NETWORK_STATE` | Détection de l'état réseau. |
| `android.permission.CAMERA` | Prise d'une photo de profil ou de galerie pendant l'inscription. |

Permissions **non déclarées** :

- aucune permission de localisation ;
- aucune permission d'appel téléphonique ;
- aucune permission de stockage ou de lecture globale des photos.

La galerie utilise le sélecteur système. Les liens `tel:`, cartes et itinéraires ouvrent une application externe ; ils ne donnent pas à Index Canada un accès direct aux appels ou à la position de l'appareil. Les filtres ou adresses saisis ne doivent pas être présentés comme une géolocalisation automatique.

## 4. Sécurité des données — inventaire préliminaire

**Ne pas copier cet inventaire tel quel dans Play Console.** Le formulaire final doit provenir d'une observation de la version signée connectée au backend Wix/Stripe de production, y compris les SDK tiers. Google précise que le développeur est responsable de l'exactitude complète de la déclaration.

| Type potentiel | Observation actuelle | Validation requise avant soumission |
| --- | --- | --- |
| Coordonnées professionnelles | Le parcours d'inscription peut transmettre à Wix le nom, l'entreprise, le courriel, le téléphone, l'adresse, le site et la description fournis par l'utilisateur. | Confirmer les champs exacts, leur caractère obligatoire/facultatif, la finalité, la conservation et la suppression. |
| Photos et vidéos | Des photos choisies ou prises peuvent être envoyées à Wix Media Manager pour le profil/la galerie. | Confirmer qu'aucun Base64 n'est stocké en collection, documenter conservation et suppression. |
| Paiement | Stripe traite le paiement natif ; Wix conserve des identifiants et statuts nécessaires au rapprochement. L'application ne doit pas enregistrer les données complètes de carte. | Observer les données envoyées par le SDK Stripe et déclarer les catégories/finalités exigées par Google Play. |
| Localisation de l'appareil | Aucune permission Android de localisation n'est déclarée. | Vérifier qu'aucun SDK ou appel réseau ne collecte une position ou une localisation approximative. |
| Activité dans l'application | Firebase Analytics est désactivé et ne doit pas être déclaré actif. | Vérifier les autres SDK, journaux serveur et données de diagnostic avant de répondre « non collecté ». |
| Favoris | Le comportement doit être vérifié pour déterminer s'ils restent uniquement sur l'appareil ou sont transmis. | Observer le trafic et documenter le stockage réel. |
| Identifiants de l'appareil et diagnostics | Non déterminé par la seule lecture des permissions. | Auditer Flutter, Stripe, Wix et tout SDK présent dans l'artefact signé. |

Avant de remplir le formulaire :

- publier une politique de confidentialité accessible dans l'application et sur une URL publique ;
- confirmer le chiffrement en transit pour tous les domaines contactés ;
- documenter la suppression et la conservation des données ;
- déterminer si l'inscription crée un « compte d'application » au sens de Google Play ; si oui, fournir un parcours de suppression dans l'application et un lien Web fonctionnel ;
- refléter les pratiques de toutes les versions encore distribuées sous ce package.

Références officielles :

- [Formulaire Sécurité des données](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Suppression de compte et de données](https://support.google.com/googleplay/android-developer/answer/13327111)

## 5. Éléments graphiques

### Icône

Le fichier `assets/images/store.png` est actuellement un PNG de 512 × 512 px. Il reste à vérifier visuellement contre les règles de contenu et de marge de Google Play avant de l'utiliser.

Exigences Google Play actuellement documentées : PNG 32 bits, 512 × 512 px, taille maximale de 1 024 Ko.

### Bannière principale

- À produire et approuver.
- Format requis : JPEG ou PNG 24 bits sans transparence.
- Dimensions : 1 024 × 500 px.

### Captures d'écran

- Capturer la version candidate installée depuis le canal de test Google Play, sans données personnelles réelles.
- Montrer des parcours réellement fonctionnels en français et en anglais.
- Fournir au moins deux captures conformes pour publier la fiche ; quatre captures de haute qualité sont recommandées par Google pour certains emplacements de découverte.
- Ne pas montrer le paiement Web comme disponible.
- Ajouter un texte alternatif descriptif à chaque image.

Référence officielle : [Ajouter des éléments d'aperçu à la fiche Play Store](https://support.google.com/googleplay/android-developer/answer/9866151)

## 6. Configuration Play Console à terminer

- [ ] Vérifier le profil développeur et les coordonnées publiques.
- [ ] Créer ou confirmer l'application avec le package `ca.indexcanada.app`.
- [ ] Activer Play App Signing et protéger la clé d'envoi.
- [ ] Produire un AAB **signé** avec les valeurs Wix/Stripe de production approuvées.
- [ ] Tester cet AAB depuis le canal interne sur un appareil Android réel.
- [ ] Ajouter les fiches locales français (Canada) et anglais (Canada).
- [ ] Ajouter l'icône, la bannière, les captures et leurs textes alternatifs.
- [ ] Fournir l'URL de politique de confidentialité.
- [ ] Compléter Sécurité des données, accès à l'application, présence de publicité, public cible, classification du contenu et toutes les déclarations affichées par Play Console.
- [ ] Vérifier les exigences de suppression de compte/données.
- [ ] Confirmer les coordonnées de support et le processus de traitement des demandes.
- [ ] Effectuer un déploiement progressif seulement après la décision GO de `production_checklist.md`.

Pour un compte développeur personnel créé après le 13 novembre 2023, Google documente actuellement un test fermé avec au moins 12 testeurs inscrits sans interruption pendant 14 jours avant la demande d'accès à la production. Vérifier l'exigence affichée directement dans le compte, car elle dépend du type et de l'ancienneté du compte.

Référence officielle : [Exigences de test pour les nouveaux comptes personnels](https://support.google.com/googleplay/android-developer/answer/14151465)

## 7. Notes de version proposées

Les notes finales doivent décrire uniquement les changements visibles et validés de la version soumise. Exemple à adapter après QA :

> Amélioration de la navigation bilingue, de l'accessibilité et de la stabilité. Mise à jour des parcours de consultation des professionnels, partenaires et offres.

Ne pas publier de calendrier, projection de revenus, volume d'utilisateurs, taux de pénétration ou promesse de succès sans étude et source vérifiables.
