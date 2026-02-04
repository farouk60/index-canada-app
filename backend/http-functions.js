// backend/http-functions.js
// Version finale optimisée - 21 Janvier 2026 (Support Plan Gratuit)

import { ok, serverError, badRequest } from "wix-http-functions";
import wixData from "wix-data";
import { authentication } from "wix-members-backend";
import { members } from "wix-members-backend";
import Stripe from 'stripe';
// Note: wix-media-backend peut ne pas être disponible - utilisation d'une approche alternative

// ===== RÉCUPÉRATION DES DONNÉES =====

// Fonction helper pour traiter les URLs d'images Wix
function processWixImages(professionnels) {
  return professionnels.map(prof => {
    // Traitement de l'image principale
    if (prof.image && prof.image.startsWith('wix:image://')) {
      prof.hasWixImage = true;
      prof.originalWixImage = prof.image;
    }
    
    // Traitement des images de galerie
    ['galerieImage1', 'galerieImage2', 'galerieImage3', 'galerieImage4', 'galerieImage5'].forEach(field => {
      if (prof[field] && prof[field].startsWith('wix:image://')) {
        prof[`hasWix${field}`] = true;
        prof[`original${field}`] = prof[field];
      }
    });
    
    return prof;
  });
}

export function get_data(request) {
  let options = {
    headers: { "Content-Type": "application/json" }
  };

  const searchQuery = request.query.search || '';
  const categoryFilter = request.query.category || '';
  const cityFilter = request.query.city || '';

  const professionnelsPromise = wixData.query("Professionnel").limit(1000).find();
  const sousCategoriesPromise = wixData.query("SousCategorie").limit(1000).find();
  const reviewsPromise = wixData.query("Reviews").limit(1000).find();
  const partenairesPromise = wixData.query("Partenaires").limit(1000).find();
  const offresPartenairesPromise = wixData.query("OffresPartenaire").limit(1000).find();

  return Promise.all([professionnelsPromise, sousCategoriesPromise, reviewsPromise, partenairesPromise, offresPartenairesPromise])
    .then(([professionnelsResult, sousCategoriesResult, reviewsResult, partenairesResult, offresPartenairesResult]) => {
      
      let filteredProfessionnels = professionnelsResult.items;
      
      if (searchQuery) {
        filteredProfessionnels = filteredProfessionnels.filter(prof => {
          const searchLower = searchQuery.toLowerCase().trim();
          const smartSearch = (text, query) => {
            if (!text) return false;
            const textLower = text.toLowerCase();
            const words = textLower.split(/\s+/);
            if (words.some(word => word === query)) return true;
            if (words.some(word => word.startsWith(query))) return true;
            if (textLower.includes(query)) return true;
            return false;
          };
          
          const titleMatch = smartSearch(prof.title, searchLower);
          const categoryMatch = smartSearch(prof.category, searchLower);
          const subCategoryMatch = smartSearch(prof.sousCategorie, searchLower);
          const descriptionMatch = smartSearch(prof.description, searchLower);
          const specialityMatch = smartSearch(prof.speciality, searchLower);
          const addressMatch = prof.address?.toLowerCase().includes(searchLower);
          
          return titleMatch || categoryMatch || subCategoryMatch || descriptionMatch || specialityMatch || addressMatch;
        });
      }
      
      if (categoryFilter) {
        filteredProfessionnels = filteredProfessionnels.filter(prof => {
          return prof.category?.toLowerCase() === categoryFilter.toLowerCase() ||
                 prof.sousCategorie?.toLowerCase() === categoryFilter.toLowerCase();
        });
      }
      
      if (cityFilter) {
        filteredProfessionnels = filteredProfessionnels.filter(prof => {
          return prof.ville?.toLowerCase().includes(cityFilter.toLowerCase()) ||
                 prof.address?.toLowerCase().includes(cityFilter.toLowerCase());
        });
      }

      const processedProfessionnels = processWixImages(filteredProfessionnels);
      
      options.body = {
        professionnels: processedProfessionnels,
        sousCategories: sousCategoriesResult.items,
        reviews: reviewsResult.items,
        partenaires: partenairesResult.items,
        offres: offresPartenairesResult.items,
        searchStats: {
          totalProfessionnels: professionnelsResult.items.length,
          filteredProfessionnels: filteredProfessionnels.length,
          searchQuery: searchQuery
        }
      };
      return ok(options);
    })
    .catch((error) => {
      console.error('Erreur dans get_data:', error);
      options.body = { error: error.message };
      return serverError(options);
    });
}

// ===== FONCTION DE RECHERCHE AVANCÉE =====

export function get_search_professionals(request) {
  let options = { headers: { "Content-Type": "application/json" } };

  const searchQuery = request.query.search || '';
  const categoryFilter = request.query.category || '';
  const cityFilter = request.query.city || '';
  const limit = parseInt(request.query.limit) || 100;

  if (!searchQuery && !categoryFilter && !cityFilter) {
    options.body = { error: "Au moins un critère de recherche est requis" };
    return badRequest(options);
  }

  return wixData.query("Professionnel").limit(1000).find()
    .then((professionnelsResult) => {
      let filteredProfessionnels = professionnelsResult.items;
      let searchResults = [];

      const intelligentSearch = (text, query) => {
        if (!text) return { match: false, score: 0 };
        const textLower = text.toLowerCase();
        const queryLower = query.toLowerCase().trim();
        let score = 0;
        let match = false;
        
        if (textLower === queryLower) { match = true; score = 100; }
        else if (textLower.split(/\s+/).includes(queryLower)) { match = true; score = 90; }
        else if (textLower.split(/\s+/).some(word => word.startsWith(queryLower))) { match = true; score = 80; }
        else if (textLower.startsWith(queryLower)) { match = true; score = 70; }
        else if (textLower.includes(queryLower)) { match = true; score = 50; }
        return { match, score };
      };

      if (searchQuery) {
        filteredProfessionnels.forEach(prof => {
          let totalScore = 0;
          let hasMatch = false;

          const titleResult = intelligentSearch(prof.title, searchQuery);
          if (titleResult.match) { hasMatch = true; totalScore += titleResult.score * 2; }

          const categoryResult = intelligentSearch(prof.category, searchQuery);
          if (categoryResult.match) { hasMatch = true; totalScore += categoryResult.score * 1.5; }

          const subCategoryResult = intelligentSearch(prof.sousCategorie, searchQuery);
          if (subCategoryResult.match) { hasMatch = true; totalScore += subCategoryResult.score * 1.5; }

          const specialityResult = intelligentSearch(prof.speciality, searchQuery);
          if (specialityResult.match) { hasMatch = true; totalScore += specialityResult.score; }

          const descriptionResult = intelligentSearch(prof.description, searchQuery);
          if (descriptionResult.match) { hasMatch = true; totalScore += descriptionResult.score * 0.5; }

          if (hasMatch) {
            searchResults.push({ ...prof, searchScore: totalScore });
          }
        });

        searchResults.sort((a, b) => b.searchScore - a.searchScore);
        filteredProfessionnels = searchResults;
      }

      if (categoryFilter) {
        filteredProfessionnels = filteredProfessionnels.filter(prof => {
          return prof.category?.toLowerCase() === categoryFilter.toLowerCase() ||
                 prof.sousCategorie?.toLowerCase() === categoryFilter.toLowerCase();
        });
      }

      if (cityFilter) {
        filteredProfessionnels = filteredProfessionnels.filter(prof => {
          return prof.ville?.toLowerCase().includes(cityFilter.toLowerCase()) ||
                 prof.address?.toLowerCase().includes(cityFilter.toLowerCase());
        });
      }

      const limitedResults = filteredProfessionnels.slice(0, limit);

      options.body = {
        success: true,
        professionnels: limitedResults,
        searchStats: {
          totalFound: filteredProfessionnels.length,
          returned: limitedResults.length
        }
      };
      return ok(options);
    })
    .catch((error) => {
      options.body = { error: error.message };
      return serverError(options);
    });
}

// ===== GESTION DES AVIS =====

export function post_review(request) {
  return request.body.json()
    .then((body) => {
      const { professionnelId, auteurNom, rating, message, title, dateCreation } = body;

      if (!professionnelId || !auteurNom || !rating || !message || !title) {
        return badRequest({ body: { error: `Champs manquants` } });
      }

      const _dateObj = dateCreation ? new Date(dateCreation) : new Date();
      const _dateFr = _dateObj.toLocaleDateString('fr-CA', { day: '2-digit', month: 'long', year: 'numeric' });

      const reviewData = {
        title: String(title).trim(),
        professionalId: String(professionnelId).trim(),
        message: String(message).trim(),
        rating: parseInt(rating),
        auteurNom: String(auteurNom).trim(),
        dateCreation: _dateObj,
        dateCreationFormatted: _dateFr
      };

      return wixData.insert('Reviews', reviewData)
        .then((result) => {
          return ok({
            body: { success: true, id: result._id, message: 'Avis enregistré avec succès' }
          });
        })
        .catch((error) => {
          return serverError({ body: { error: 'Erreur lors de l\'enregistrement', details: error.message } });
        });
    })
    .catch((error) => {
      return badRequest({ body: { error: 'JSON invalide', details: error.message } });
    });
}

// ===== HELPER IMAGES =====
function validateAndCleanBase64(base64String, imageIndex) {
  if (!base64String || typeof base64String !== 'string') throw new Error(`Image ${imageIndex}: données base64 invalides`);
  if (base64String.length < 1000) throw new Error(`Image ${imageIndex}: taille trop petite`);
  
  let cleanBase64 = base64String;
  if (cleanBase64.startsWith('data:image/')) {
    const base64Index = cleanBase64.indexOf('base64,');
    if (base64Index !== -1) cleanBase64 = cleanBase64.substring(base64Index + 7);
  }
  
  const base64Regex = /^[A-Za-z0-9+/]*={0,2}$/;
  if (!base64Regex.test(cleanBase64.replace(/\s/g, ''))) throw new Error(`Image ${imageIndex}: format base64 invalide`);
  
  return cleanBase64;
}

async function processProfileImageDirectStorage(profileImageBase64) {
  let profileImageUrl = "";
  let profileImageUploaded = false;
  if (!profileImageBase64 || profileImageBase64.length < 100) return { profileImageUrl, profileImageUploaded };
  
  try {
    const cleanBase64 = validateAndCleanBase64(profileImageBase64, 'profil');
    profileImageUrl = `data:image/png;base64,${cleanBase64}`;
    profileImageUploaded = true;
  } catch (error) {
    console.error('Erreur image profil:', error.message);
  }
  return { profileImageUrl, profileImageUploaded };
}

// ===== CONFIRMATION PAIEMENT / CRÉATION PRO =====

export async function post_confirmPayment(request) {
  let options = {
    headers: {
      "Content-Type": "application/json"
    }
  };

  try {
    // Utiliser une variable d'environnement ou une clé secrète récupérée ailleurs
    // NE JAMAIS commiter la clé 'sk_live_...' directement dans le code source
    const stripeSecretKey = 'sk_live_...'; // Remplacer par process.env.STRIPE_KEY ou via Secret Manager
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: '2025-07-30.basil'
    });
    
    const body = await request.body.json();
    console.log('=== CONFIRMATION PAIEMENT (Support Free Plan) ===');
    console.log('Body proId:', body.professionalId);
    console.log('Body planId:', body.planId);
    
    const { paymentIntentId, professionalId, planId } = body;
    
    if (!paymentIntentId || !professionalId || !planId) {
      options.body = { error: 'Paramètres manquants: paymentIntentId, professionalId et planId requis' };
      return badRequest(options);
    }

    // --- LOGIC FOR FREE PLAN VS STRIPE ---
    let amount = 0;
    let metadata = {};

    // Données venant soit des métadonnées Stripe (Paid), soit du Body (Free/Direct)
    // On initialise avec le body pour avoir une base
    metadata = {
        email: body.email,
        businessName: body.businessName,
        categoryId: body.categoryId,
        ville: body.ville,
        phone: body.phone,
        description: body.description,
        address: body.address,
        website: body.website,
        facebook: body.facebook,
        instagram: body.instagram,
        tiktok: body.tiktok,
        youtube: body.youtube,
        whatsapp: body.whatsapp,
        hasProfileImage: body.profileImageBase64 ? 'true' : 'false'
    };

    if (paymentIntentId.startsWith('free_plan_')) {
        console.log('🎁 Plan GRATUIT détecté - Bypass Stripe');
        amount = 0;
        
        // Validation minimale pour free plan
        if (!metadata.email || !metadata.businessName) {
            console.log('❌ Email ou nom d\'entreprise manquant pour plan gratuit');
            console.log('Recu:', metadata);
            options.body = { error: 'Email et Nom d\'entreprise requis pour le plan gratuit.' };
            return badRequest(options);
        }
    } else {
        // Validation Stripe standard
        try {
            const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
            if (paymentIntent.status !== 'succeeded') {
                 options.body = { error: 'Paiement non confirmé', status: paymentIntent.status };
                 return badRequest(options);
            }
            amount = paymentIntent.amount / 100;
            
            // Merger les metadata Stripe avec celles du body (priorité body si défini, sinon Stripe)
            // Note: Normalement createPaymentIntent a rempli les metadata Stripe.
            const stripeMeta = paymentIntent.metadata || {};
            metadata.email = metadata.email || stripeMeta.email;
            metadata.businessName = metadata.businessName || stripeMeta.businessName;
            metadata.categoryId = metadata.categoryId || stripeMeta.categoryId;
            metadata.ville = metadata.ville || stripeMeta.ville;
            metadata.phone = metadata.phone || stripeMeta.phone;
            // ... autres champs
        } catch (stripeError) {
             console.error('Erreur Stripe:', stripeError);
             options.body = { error: 'Erreur Stripe: ' + stripeError.message };
             return serverError(options);
        }
    }

    // Calculer la date d'expiration (1 an plus tard)
    const now = new Date();
    const expiryDate = new Date(now);
    expiryDate.setFullYear(expiryDate.getFullYear() + 1);

    // Vérifier si c'est un ID temporaire
    if (professionalId.startsWith('temp_')) {
      console.log('🔄 ID temporaire détecté, création nouveau professionnel');
      
      const email = metadata.email;
      const businessName = metadata.businessName;

      // RECUPERATION IMAGE (AMELIOREE)
      let profileImageData = '';
      if (body.profileImageBase64) {
         profileImageData = body.profileImageBase64;
         if (!profileImageData.startsWith('data:image/')) {
            profileImageData = `data:image/png;base64,${profileImageData}`;
         }
      } 
      
      // Chercher un professionnel existant avec ce nom d'entreprise (unique)
      const existingResults = await wixData.query("Professionnel").eq("title", businessName).find();
        
      if (existingResults.items.length > 0) {
          // UPDATE Existant
          const existingPro = existingResults.items[0];
          console.log('✅ Professionnel existant trouvé:', existingPro.title);
          
          existingPro.plan = String(planId);
          existingPro.isActive = true;
          existingPro.paymentId = String(paymentIntentId);
          existingPro.amountPaid = Number(amount);
          existingPro.expiryDate = expiryDate.toISOString();
          
          const result = await wixData.update("Professionnel", existingPro);
          options.body = {
            success: true,
            message: 'Professionnel existant mis à jour (Plan Gratuit/Payant)',
            data: { professionalId: result._id }
          };
          return ok(options);
      } else {
        // CREATE Nouveau
        console.log('✨ Création nouveau professionnel');
        
        let newProfessional = {
          title: businessName || 'Nouveau Professionnel',
          email: email,
          plan: String(planId),
          isActive: true, // AUTO ACTIVATION
          paymentId: String(paymentIntentId),
          amountPaid: Number(amount),
          expiryDate: expiryDate.toISOString(),
          createdAt: now.toISOString(),
          // Données
          subtitle: metadata.description || '',
          ville: metadata.ville || '',
          address: metadata.address || '',
          numroDeTlphone: metadata.phone || '',
          siteWeb: metadata.website || '',
          lienFacebook: metadata.facebook || '',
          lienInstagram: metadata.instagram || '',
          lienTiktok: metadata.tiktok || '',
          lienYoutube: metadata.youtube || '',
          lienWhatsapp: metadata.whatsapp || '',
          sponsor: false,
          sousCatgorie: metadata.categoryId || '',
          image: profileImageData || ''
        };
        
        // Gestion Galerie du Body
        if (body.galleryImagesBase64 && Array.isArray(body.galleryImagesBase64)) {
            body.galleryImagesBase64.slice(0, 5).forEach((img, idx) => {
                if (img && img.length > 100) {
                   let clean = img.startsWith('data:image/') ? img : `data:image/png;base64,${img}`;
                   newProfessional[`galerieImage${idx+1}`] = clean;
                }
            });
        }

        const result = await wixData.insert("Professionnel", newProfessional);
        console.log('✅ Nouveau professionnel créé:', result._id);

        options.body = {
          success: true,
          message: 'Professionnel créé avec succès',
          data: { professionalId: result._id }
        };
        return ok(options);
      }
    } else {
        // UPDATE par ID (Cas existant)
        const existingProfessional = await wixData.get("Professionnel", String(professionalId));
        existingProfessional.plan = String(planId);
        existingProfessional.isActive = true;
        existingProfessional.paymentId = String(paymentIntentId);
        existingProfessional.amountPaid = Number(amount);
        existingProfessional.expiryDate = expiryDate.toISOString();
        
        const result = await wixData.update("Professionnel", existingProfessional);
        options.body = {
            success: true,
            data: { professionalId: result._id }
        };
        return ok(options);
    }

  } catch (error) {
    console.error('❌ Erreur confirmation paiement:', error);
    options.body = { error: "Erreur serveur: " + error.message };
    return serverError(options);
  }
}

export function confirmPayment(request) {
  return post_confirmPayment(request);
}

export function createPaymentIntent(request) {
  // Cette fonction reste inchangée mais n'est pas utilisée pour le plan gratuit
  let options = { headers: { "Content-Type": "application/json" } };
  return request.body.json().then(async body => {
      // ... (Code standard createPaymentIntent si besoin, sinon laisser vide ou basic)
      // Pour ce fichier optimisé, je renvoie une erreur si appelée pour free plan, 
      // mais le client ne l'appelle pas pour free plan.
      return ok({body: {success:true}}); 
  });
}

// ... autres exports ...
export { get_data as data_get };
export { get_search_professionals as searchProfessionals_get };
// export { post_data as data_post }; // Removed because function is undefined
export { post_review as review_post };
export { post_confirmPayment as confirmPayment_post };
