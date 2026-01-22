
import { ok, badRequest, serverError } from 'wix-http-functions';
import wixData from 'wix-data';
import wixSecretsBackend from 'wix-secrets-backend';
const stripe = require('stripe');

// Fonction utilitaire pour initialiser Stripe
async function getStripe() {
    const key = await wixSecretsBackend.getSecret('stripeSecretKey'); // Assurez-vous d'avoir ce secret
    return stripe(key);
}

// ... autres fonctions ...

export async function post_confirmPayment(request) {
    try {
        const body = await request.body.json();
        const { paymentIntentId, professionalId, planId, businessName, profileImageBase64, galleryImagesBase64 } = body;

        console.log(`Confirming payment for: ${businessName} (Plan: ${planId})`);

        let isFreePlan = false;

        // 1. Validation du paiement avec Stripe (Sauf si c'est un plan gratuit)
        if (paymentIntentId && paymentIntentId.startsWith('free_plan_')) {
            console.log('✅ Plan gratuit détecté - Bypass de la vérification Stripe');
            isFreePlan = true;
        } else {
            // Vérification standard Stripe
            const stripeClient = await getStripe();
            try {
                const paymentIntent = await stripeClient.paymentIntents.retrieve(paymentIntentId);
                if (paymentIntent.status !== 'succeeded') {
                    return badRequest({ body: { error: 'Le paiement n\'a pas réussi ou est en attente.' } });
                }
            } catch (stripeError) {
                console.error('Erreur Stripe:', stripeError);
                return badRequest({ 
                    body: { error: `Erreur lors de la confirmation du paiement: ${stripeError.message}` } 
                });
            }
        }

        // 2. Création/Mise à jour du Professionnel dans la base Wix
        // Note: professionalId ici est peut-être temporaire ("temp_..."). 
        // En création réelle, on laisse Wix générer l'ID ou on utilise l'ID existant si update.
        
        const isTempId = professionalId && professionalId.startsWith('temp_');
        
        const newProData = {
            title: businessName,
            email: body.email || "", // Assurez-vous de passer l'email si dispo
            plan: planId,
            statut: 'Actif', // Ou 'En attente' selon votre logique
            dateInscription: new Date(),
            paiementId: paymentIntentId
        };
        
        // Ajouter d'autres champs nécessaires ici pour la collection 'Professionnels' ou 'Members'
        // ...

        let savedPro;
        
        // Logique simplifiée : Création d'une nouvelle entrée de demande ou update
        // Adaptez "Requests" ou "Professionnels" selon votre vraie collection
        
        // Exemple d'insertion dans une collection "Professionnels"
        // Si c'est un ID temporaire, on insert un nouveau
        if (isTempId) {
             savedPro = await wixData.insert('Professionnels', newProData);
        } else {
             // Si ID existant, on update (logique à adapter)
             newProData._id = professionalId;
             savedPro = await wixData.save('Professionnels', newProData);
        }

        // 3. Gestion des images (Si envoyées en Base64)
        // Note: Le code d'upload d'images Wix est complexe et nécessite wix-media-backend.
        // Si vous avez déjà une fonction active pour ça, gardez-la.
        // Ici nous assumons que le succès du paiement suffit pour retourner OK.
        
        return ok({
            body: {
                success: true,
                data: {
                    professionalId: savedPro._id, // Renvoie le VIAI ID Wix
                    hasImage: false // À changer si vous traitez les images ici
                }
            }
        });

    } catch (error) {
        console.error('Erreur API confirmPayment:', error);
        return serverError({
            body: { error: `Erreur serveur: ${error.message}` }
        });
    }
}
