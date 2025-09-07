// ===== FONCTION DE REVIEW CORRIGÉE POUR REMPLACER DANS HTTP-FUNCTIONS.JS =====

import { ok, badRequest, serverError } from 'wix-http-functions';
import wixData from 'wix-data';

export function post_review(request) {
  return request.body.json()
    .then((body) => {
      // Utiliser les noms de champs qui correspondent à votre collection Wix
      const { professionnelId, auteurNom, rating, message, title, dateCreation } = body;

      console.log('Données reçues:', body);

      // Vérifier les champs requis selon votre structure Wix
      if (!professionnelId || !auteurNom || !rating || !message || !title) {
        console.error('Champs manquants:', { professionnelId, auteurNom, rating, message, title });
        return badRequest({
          body: { error: 'Champs requis manquants: professionnelId, auteurNom, rating, message, title' }
        });
      }

      // Préparer la date et une version formatée en français pour l'affichage dans Wix
      const _dateObj = dateCreation ? new Date(dateCreation) : new Date();
      const _dateFr = _dateObj.toLocaleDateString('fr-CA', { day: '2-digit', month: 'long', year: 'numeric' });

      // Enregistrer dans la collection Reviews avec les IDs de champs corrects de Wix
      const reviewData = {
        title,                            // Champ "Title" - ID: title
        professionalId: professionnelId,  // Champ "professionalId" - ID: professionalId (correspond au nom de variable)
        message,                          // Champ "message" - ID: message
        rating,                           // Champ "rating" - ID: rating
        auteurNom,                        // Champ "auteurNom" - ID: auteurNom
        dateCreation: _dateObj,           // Champ "Datecreation" - ID: dateCreation (type Date)
        dateCreationFormatted: _dateFr    // Nouveau champ texte pour affichage: ex. "12 août 2025"
      };

      console.log('Données à insérer:', reviewData);

      return wixData.insert('Reviews', reviewData)
      .then((savedItem) => {
        console.log('Avis enregistré avec succès:', savedItem._id);
        return ok({
          body: { success: true, itemId: savedItem._id }
        });
      })
      .catch((err) => {
        console.error('Erreur wixData.insert:', err);
        return serverError({
          body: { error: `Erreur lors de l'enregistrement: ${err.message}` }
        });
      });
    })
    .catch((err) => {
      console.error('Erreur parsing JSON:', err);
      return badRequest({
        body: { error: 'JSON invalide' }
      });
    });
}

// === LISTER LES AVIS D'UN PROFESSIONNEL ===
// URL: GET /_functions/reviews/{professionalId}
export function get_reviews(request) {
  try {
    const path = request.path || [];
    const professionalId = Array.isArray(path) && path.length > 0 ? path[0] : null;

    if (!professionalId) {
      return badRequest({ body: { error: 'ID professionnel manquant dans l’URL' } });
    }

    // Requête principale + rétrocompatibilité (anciens enregistrements avec champ 'image')
    const q1 = wixData.query('Reviews').eq('professionalId', professionalId);
    const q2 = wixData.query('Reviews').eq('image', professionalId);

    return q1
      .or(q2)
      .descending('dateCreation')
      .find()
      .then((results) => {
        const items = results.items || [];
        const reviews = items.map((it) => ({
          _id: it._id,
          professionalId: it.professionalId || it.image || '',
          auteurNom: it.auteurNom || '',
          rating: it.rating || 0,
          message: it.message || '',
          title: it.title || '',
          dateCreation: it.dateCreation || null,
          dateCreationFormatted: it.dateCreationFormatted || null,
        }));

        return ok({
          headers: { 'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate' },
          body: { reviews },
        });
      })
      .catch((err) => {
        console.error('Erreur get_reviews:', err);
        return serverError({ body: { error: err.message } });
      });
  } catch (e) {
    return serverError({ body: { error: e.message } });
  }
}
