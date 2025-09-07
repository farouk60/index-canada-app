import { ok, badRequest, serverError } from 'wix-http-functions';
import wixData from 'wix-data';

// NOUVELLE FONCTION POUR CORRIGER LE PROBLÈME D'AVIS
export function post_review(request) {
  console.log('🔥 NOUVELLE FONCTION V2 ACTIVÉE 🔥');
  
  return request.body.json()
    .then((body) => {
      console.log('📥 Données reçues:', JSON.stringify(body, null, 2));
      
      const { professionnelId, auteurNom, rating, message, title, dateCreation } = body;

      console.log('📋 Champs extraits:', {
        professionnelId,
        auteurNom,
        rating,
        message,
        title,
        dateCreation
      });

      // Validation
      if (!professionnelId || !auteurNom || !rating || !message || !title) {
        const missing = [];
        if (!professionnelId) missing.push('professionnelId');
        if (!auteurNom) missing.push('auteurNom');
        if (!rating) missing.push('rating');
        if (!message) missing.push('message');
        if (!title) missing.push('title');
        
        console.error('❌ Champs manquants:', missing);
        return badRequest({
          body: { 
            error: `Champs manquants: ${missing.join(', ')}`,
            function: 'post_review_v2',
            received: body
          }
        });
      }

      // Préparer la date (type Date) et une version formatée FR (texte)
      const _dateObj = dateCreation ? new Date(dateCreation) : new Date();
      const _dateFr = _dateObj.toLocaleDateString('fr-CA', { day: '2-digit', month: 'long', year: 'numeric' });

      // Données pour Wix selon votre structure
      const reviewData = {
        title: String(title).trim(),
        professionalId: String(professionnelId).trim(), // stocker l'ID pro dans le bon champ
        message: String(message).trim(),
        rating: parseInt(rating),
        auteurNom: String(auteurNom).trim(),
        dateCreation: _dateObj,
        dateCreationFormatted: _dateFr
      };

      console.log('💾 Insertion dans Wix Reviews:', JSON.stringify(reviewData, null, 2));

      return wixData.insert('Reviews', reviewData)
        .then((result) => {
          console.log('✅ SUCCÈS! Avis créé avec ID:', result._id);
          return ok({
            body: {
              success: true,
              id: result._id,
              message: 'Avis enregistré avec succès (v2)',
              function: 'post_review_v2'
            }
          });
        })
        .catch((error) => {
          console.error('❌ Erreur Wix:', error);
          return serverError({
            body: {
              error: 'Erreur lors de l\'enregistrement',
              details: error.message,
              function: 'post_review_v2',
              data: reviewData
            }
          });
        });
    })
    .catch((error) => {
      console.error('❌ Erreur JSON:', error);
      return badRequest({
        body: {
          error: 'JSON invalide',
          details: error.message,
          function: 'post_review_v2'
        }
      });
    });
}
