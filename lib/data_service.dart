import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'models/wix_partner_models.dart';
import 'models/wix_offer_models.dart';

// Helper function to parse JSON in isolate
Map<String, dynamic> _parseJson(String jsonString) {
  return json.decode(jsonString);
}

// Helper function pour logs conditionnels en production
void _debugLog(String message) {
  if (kDebugMode) {
    print(message);
  }
}

class DataService {
  static const String baseUrl = 'https://www.immigrantindex.com/_functions/data';

  // Configuration pour les tests de performance
  static const bool SIMULATION_MODE = false; // Désactivé par défaut
  static const int SIMULATION_PROFESSIONALS_COUNT = 100000;
  static const int SIMULATION_SERVICES_COUNT = 50;

  // Singleton pattern pour éviter les instances multiples
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // Cache local avec expiration pour optimiser Wix
  Map<String, dynamic>? _cachedData;
  
  // Gestion des requêtes multiples pour éviter les appels en cascade
  Completer<Map<String, dynamic>>? _pendingRequest;
  bool _isRequestInProgress = false;

  /// Vide le cache pour forcer le rechargement des données
  void clearCache() {
    _cachedData = null;
    _debugLog('🗑️ Cache DataService vidé');
  }

  /// Force une synchronisation complète avec la base de données Wix
  Future<void> forceSyncWithWix() async {
    _debugLog('🔄 FORÇAGE DE LA SYNCHRONISATION WIX');
    
    _cachedData = null;
    try {
      await _fetchAllData(forceRefresh: true);
      _debugLog('✅ Synchronisation Wix terminée avec succès');
    } catch (e) {
      _debugLog('❌ Erreur lors de la synchronisation Wix: $e');
      throw e;
    }
  }

  Future<Map<String, dynamic>> fetchAllData() async {
    // Si on a déjà une requête en cours, on la partage
    if (_isRequestInProgress && _pendingRequest != null) {
      print('✅ Requête en cours détectée, attente de la réponse partagée');
      return await _pendingRequest!.future;
    }

    // Vérifier le cache en premier
    if (_cachedData != null) {
      print('✅ Données servies depuis le cache');
      return _cachedData!;
    }

    return await _fetchAllData(forceRefresh: false);
  }

  /// Méthode privée pour récupérer les données depuis l'API
  Future<Map<String, dynamic>> _fetchAllData({bool forceRefresh = false}) async {
    // Éviter les requêtes multiples simultanées (même si forceRefresh est demandé)
    // On attend la requête en cours pour éviter les courses aux accès sur _pendingRequest
    if (_isRequestInProgress && _pendingRequest != null) {
      return await _pendingRequest!.future;
    }

    _isRequestInProgress = true;
    _pendingRequest = Completer<Map<String, dynamic>>();
    final localCompleter = _pendingRequest!; // capturer une référence stable

    try {
      print('🌐 Récupération des données depuis Wix...');
      
      // Ajouter un timestamp pour éviter le cache côté serveur/navigateur
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$baseUrl?t=$timestamp');

      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout: La récupération des données a pris trop de temps');
        },
      );
      
      print('DataService: Response status: ${response.statusCode}');
      print('DataService: Response length: ${response.body.length} characters');
      
      if (response.statusCode == 200) {
        final data = await compute(_parseJson, response.body);
        
        // Mettre en cache les données
        _cachedData = data;
        
        print('✅ Données récupérées et mises en cache avec succès');
        if (!localCompleter.isCompleted) {
          localCompleter.complete(data);
        }
        
        return data;
      } else {
        throw Exception('Erreur HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur lors de la récupération des données: $e');
      if (!localCompleter.isCompleted) {
        try {
          localCompleter.completeError(e);
        } catch (_) {
          // ignorer les erreurs de double complétion
        }
      }
      throw e;
    } finally {
      // Ne remettre à zéro que si nous sommes toujours le completer actif
      if (identical(_pendingRequest, localCompleter) || _pendingRequest == null) {
        _isRequestInProgress = false;
        _pendingRequest = null;
      }
    }
  }

  Future<List<SousCategorie>> fetchSousCategories({bool forceRefresh = false}) async {
    print('DataService: fetchSousCategories called');
    
    // Mode simulation pour les tests de performance
    if (SIMULATION_MODE) {
      return _generateSimulatedSousCategories();
    }
    
    try {
      final data = await _fetchAllData(forceRefresh: forceRefresh);

      // Handle the actual API response structure with null safety
      Map<String, dynamic>? dataToUse;
      if (data.containsKey('data')) {
        dataToUse = data['data'] as Map<String, dynamic>?;
      } else {
        dataToUse = data;
      }

      if (dataToUse == null) {
        print('DataService: dataToUse is null, returning empty list');
        return [];
      }

      final items = dataToUse['sousCategories'] as List? ?? [];
      print('DataService: Processing ${items.length} sous-categories items');
      
      var sousCategories = <SousCategorie>[];
      for (int i = 0; i < items.length; i++) {
        try {
          final item = items[i];
          if (item is Map<String, dynamic>) {
            final sousCategorie = SousCategorie.fromJson(item);
            sousCategories.add(sousCategorie);
          } else {
            print('DataService: SousCategorie item $i is not a Map<String, dynamic>: ${item.runtimeType}');
          }
        } catch (e) {
          print('DataService: Error processing sous-categorie $i: $e');
          // Continue avec les autres sous-catégories
        }
      }
      
      return sousCategories;
    } catch (e) {
      print('DataService: Error in fetchSousCategories: $e');
      return [];
    }
  }

  Future<List<Professionnel>> fetchSponsoredProfessionnels({bool forceRefresh = false}) async {
    print('DataService: fetchSponsoredProfessionnels called');
    
    try {
      final data = await _fetchAllData(forceRefresh: forceRefresh);

      // Handle the actual API response structure with null safety
      Map<String, dynamic>? dataToUse;
      if (data.containsKey('data')) {
        dataToUse = data['data'] as Map<String, dynamic>?;
      } else {
        dataToUse = data;
      }

      if (dataToUse == null) {
        print('DataService: dataToUse is null for sponsored professionals, returning empty list');
        return [];
      }

      final items = dataToUse['professionnels'] as List? ?? [];
      print('DataService: Processing ${items.length} professionals items for sponsored check');
      
      var allProfessionnels = <Professionnel>[];
      for (int i = 0; i < items.length; i++) {
        try {
          final item = items[i];
          if (item is Map<String, dynamic>) {
            final prof = Professionnel.fromJson(item);
            allProfessionnels.add(prof);
          } else {
            print('DataService: Item $i is not a Map<String, dynamic>: ${item.runtimeType}');
          }
        } catch (e) {
          print('DataService: Error processing professional $i: $e');
          // Continue avec les autres professionnels
        }
      }
      
      // Utiliser la méthode isFeatured du modèle qui gère tous les plans sponsorisés
      var sponsoredList = allProfessionnels.where((p) => p.isFeatured).toList();
      
      // Debug: Afficher les détails des professionnels en vedette
      print('DataService: Found ${sponsoredList.length} featured professionnels out of ${allProfessionnels.length} total');
      for (int i = 0; i < sponsoredList.length; i++) {
        final prof = sponsoredList[i];
        print('Featured Prof $i: ${prof.title}');
        print('  - Image: ${prof.image.isEmpty ? "EMPTY" : prof.image.substring(0, prof.image.length > 50 ? 50 : prof.image.length)}...');
        print('  - Subtitle: ${prof.subtitle.isEmpty ? "EMPTY" : prof.subtitle}');
        print('  - Ville: ${prof.ville.isEmpty ? "EMPTY" : prof.ville}');
        print('  - SousCategorie: ${prof.sousCategorie.isEmpty ? "EMPTY" : prof.sousCategorie}');
        print('  - Plan: ${prof.plan}');
      }
      
      return sponsoredList;
    } catch (e) {
      print('DataService: Error in fetchSponsoredProfessionnels: $e');
      return [];
    }
  }

  Future<List<Professionnel>> fetchProfessionnels({
    String? sousCategorie,
    String? search,
    String? ville,
    bool forceRefresh = false,
  }) async {
    // Mode simulation pour les tests de performance
    if (SIMULATION_MODE) {
      return _generateSimulatedProfessionnels();
    }

    final data = await _fetchAllData(forceRefresh: forceRefresh);

    // Handle the actual API response structure
    Map<String, dynamic> dataToUse;
    if (data.containsKey('data')) {
      dataToUse = data['data'];
    } else {
      dataToUse = data;
    }

    final items = dataToUse['professionnels'] as List? ?? [];
    var allProfessionnels = items.map((e) => Professionnel.fromJson(e)).toList();

    // Apply filters
    var filteredProfessionnels = allProfessionnels.where((prof) {
      if (sousCategorie != null && prof.sousCategorie != sousCategorie) {
        return false;
      }
      if (search != null && search.isNotEmpty) {
        final searchLower = search.toLowerCase();
        if (!prof.title.toLowerCase().contains(searchLower)) {
          return false;
        }
      }
      if (ville != null && ville.isNotEmpty && prof.ville != ville) {
        return false;
      }
      return true;
    }).toList();

    // Sort by featured status
    filteredProfessionnels.sort((a, b) {
      if (a.plan == 'premium' && b.plan != 'premium') return -1;
      if (a.plan != 'premium' && b.plan == 'premium') return 1;
      return 0;
    });

    print('DataService: ${filteredProfessionnels.length} professionnels après filtrage');
    return filteredProfessionnels;
  }

  Future<List<WixPartner>> fetchPartners({bool forceRefresh = false}) async {
    print('DataService: fetchPartners called with forceRefresh: $forceRefresh');
    
    final data = await _fetchAllData(forceRefresh: forceRefresh);

    // Handle the actual API response structure
    Map<String, dynamic> dataToUse;
    if (data.containsKey('data')) {
      dataToUse = data['data'];
    } else {
      dataToUse = data;
    }

    // Être tolérant aux différentes clés possibles côté backend
    dynamic raw = dataToUse['partenaires'] ??
        dataToUse['partners'] ??
        dataToUse['wixPartners'] ??
        dataToUse['Partners'] ??
        dataToUse['Partenaires'];

    List items;
    if (raw is List) {
      items = raw;
    } else if (raw is Map && raw['items'] is List) {
      items = raw['items'] as List;
    } else {
      items = <dynamic>[];
    }

    try {
      print('DataService: Processing ${items.length} partners from Wix collection');
      var partners = items.map((e) => WixPartner.fromJson(e)).toList();
      // Filtrer ceux qui doivent être affichés
      partners = partners.where((p) => p.shouldDisplay).toList();
      // Trier: d'abord en vedette, puis par ordre d'affichage, puis par titre
      partners.sort((a, b) {
        final featuredCmp = (b.isFeatured ? 1 : 0).compareTo(a.isFeatured ? 1 : 0);
        if (featuredCmp != 0) return featuredCmp;
        final orderCmp = a.displayOrder.compareTo(b.displayOrder);
        if (orderCmp != 0) return orderCmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      return partners;
    } catch (e) {
      print('DataService: Error parsing partners: $e');
      return [];
    }
  }

  Future<List<WixOffer>> fetchOffers({bool forceRefresh = false}) async {
    print('DataService: fetchOffers called with forceRefresh: $forceRefresh');
    
    final data = await _fetchAllData(forceRefresh: forceRefresh);

    // Handle the actual API response structure  
    Map<String, dynamic> dataToUse;
    if (data.containsKey('data')) {
      dataToUse = data['data'];
    } else {
      dataToUse = data;
    }

    final items = dataToUse['offres'] as List? ?? [];

    try {
      print('DataService: Processing ${items.length} offers from Wix collection');
      return items.map((e) => WixOffer.fromWixData(e)).toList();
    } catch (e) {
      print('DataService: Error parsing offers: $e');
      throw e;
    }
  }

  Future<List<WixOffer>> fetchValidOffers({bool forceRefresh = false}) async {
    final allOffers = await fetchOffers(forceRefresh: forceRefresh);
    return allOffers.where((offer) => offer.isValid).toList();
  }

  Future<List<WixOffer>> fetchExclusiveOffers({bool forceRefresh = false}) async {
    final allOffers = await fetchOffers(forceRefresh: forceRefresh);
    return allOffers.where((offer) => offer.isValid && offer.isExclusive).toList();
  }

  /// Recherche tous les types de données
  Future<Map<String, dynamic>> searchAll({
    String? query,
    String? ville,
    String? sousCategorie,
    bool forceRefresh = false,
  }) async {
    try {
      final professionnels = await fetchProfessionnels(
        search: query,
        ville: ville,
        sousCategorie: sousCategorie,
        forceRefresh: forceRefresh,
      );

      final sousCategories = await fetchSousCategories(forceRefresh: false);
      var filteredSousCategories = sousCategories;
      if (query != null && query.isNotEmpty) {
        filteredSousCategories = sousCategories
            .where((sc) => sc.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }

      return {
        'professionnels': professionnels,
        'sousCategories': filteredSousCategories,
      };
    } catch (e) {
      print('DataService: Error in searchAll: $e');
      throw e;
    }
  }

  /// Enregistre un nouveau professionnel
  Future<String> postProfessionalRegistration({
    required String businessName,
    required String category,
    required String email,
    required String phone,
    required String address,
    required String city,
    required String description,
    required String selectedPlan,
    required double planPrice,
    String? website,
    String? businessSummary,
    String? facebook,
    String? instagram,
    String? tiktok,
    String? youtube,
    String? whatsapp,
    String? couponTitle,
    String? couponCode,
    String? couponDescription,
    String? couponExpirationDate,
    bool? hasProfileImage,
    int? galleryImagesCount,
    String? profileImageBase64,
    List<String>? galleryImagesBase64,
  }) async {
    print('DataService: postProfessionalRegistration called for: $businessName');
    
    try {
      // Préparer les données pour l'API
      final registrationData = {
        'businessName': businessName,
        'category': category,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'description': description,
        'selectedPlan': selectedPlan,
        'planPrice': planPrice,
        'website': website,
        'businessSummary': businessSummary,
        'facebook': facebook,
        'instagram': instagram,
        'tiktok': tiktok,
        'youtube': youtube,
        'whatsapp': whatsapp,
        'couponTitle': couponTitle,
        'couponCode': couponCode,
        'couponDescription': couponDescription,
        'couponExpirationDate': couponExpirationDate,
        'hasProfileImage': hasProfileImage,
        'galleryImagesCount': galleryImagesCount,
        'profileImageBase64': profileImageBase64,
        'galleryImagesBase64': galleryImagesBase64,
      };

      // 1) Endpoint recommandé: HTTP Function Wix /_functions/professionals (voir exemple dans repo)
      final endpoints = <Uri>[
        Uri.parse('https://www.immigrantindex.com/_functions/professionals'),
        // Fallbacks selon anciennes routes
        Uri.parse('https://www.immigrantindex.com/_functions/addProfessional'),
        Uri.parse('$baseUrl/register-professional'),
      ];

      http.Response? lastResponse;
      for (final url in endpoints) {
        try {
          print('DataService: Trying registration endpoint: $url');
          final resp = await http
              .post(
                url,
                headers: {'Content-Type': 'application/json'},
                body: json.encode(registrationData),
              )
              .timeout(const Duration(seconds: 30));
          lastResponse = resp;
          print('DataService: Endpoint status: ${resp.statusCode}');
          if (resp.statusCode == 200 || resp.statusCode == 201) {
            final responseData = json.decode(resp.body);
            final professionalId = responseData['id'] ?? responseData['_id'] ?? responseData['itemId'] ?? '';
            print('DataService: Professional registered successfully with ID: $professionalId');
            clearCache();
            return professionalId.isNotEmpty ? professionalId : 'ok';
          }
        } catch (e) {
          print('DataService: Error calling $url -> $e');
          // try next
        }
      }

      if (lastResponse != null) {
        print('DataService: Registration failed - Status: ${lastResponse.statusCode}');
        print('DataService: Response body: ${lastResponse.body}');
        throw Exception('Erreur lors de l\'enregistrement: ${lastResponse.statusCode}');
      }

      throw Exception('Aucun endpoint Wix disponible pour l\'enregistrement');
    } catch (e) {
      print('DataService: Exception during registration: $e');
      throw e;
    }
  }

  /// Enregistre un nouvel avis/review
  Future<void> postReview(
    String professionnelId,
    String name,
    int rating,
    String message,
    String title,
  ) async {
    print('DataService: postReview called for professional: $professionnelId');
    
    try {
      // Préparer les données selon la structure de votre collection Wix Reviews
      final reviewData = {
        'professionnelId': professionnelId, // ID du champ: professionnelId
        'auteurNom': name,                  // ID du champ: auteurNom
        'rating': rating,                   // ID du champ: rating
        'message': message,                 // ID du champ: message
        'title': title,                     // ID du champ: title
        'dateCreation': DateTime.now().toIso8601String(), // ID du champ: dateCreation
      };

      print('DataService: Sending review data: $reviewData');

  // Endpoint pour l'enregistrement d'avis
  // Utilise directement la fonction Wix "post_review" exposée à /_functions/review
  // pour éviter le routeur legacy /_functions/data qui exige encore email/phone.
  final url = Uri.parse('https://www.immigrantindex.com/_functions/review');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(reviewData),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Timeout: Enregistrement de l\'avis trop long');
        },
      );

      print('DataService: Review post response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('DataService: Review posted successfully');
        
        // Vider le cache pour forcer un rechargement
        clearCache();
      } else {
        print('DataService: Review post failed - Status: ${response.statusCode}');
        print('DataService: Response body: ${response.body}');
        throw Exception('Erreur lors de l\'enregistrement de l\'avis: ${response.statusCode}');
      }
    } catch (e) {
      print('DataService: Exception during review post: $e');
      throw e;
    }
  }

  /// Récupère les avis pour un professionnel spécifique
  Future<List<Review>> fetchReviews(String professionnelId, {bool forceRefresh = false}) async {
    print('DataService: fetchReviews called for professional: $professionnelId');
    
    try {
      // Ajouter un timestamp pour éviter le cache côté serveur/navigateur
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Essayer d'abord l'endpoint direct, puis retomber sur le legacy si besoin
      final directUrl = Uri.parse('https://www.immigrantindex.com/_functions/reviews/$professionnelId?t=$timestamp');
      final legacyUrl = Uri.parse('$baseUrl/reviews/$professionnelId?t=$timestamp');

      Future<http.Response> _fetch(Uri url) {
        print('DataService: Fetching reviews from: $url');
        return http.get(url).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('Timeout: La récupération des avis a pris trop de temps');
          },
        );
      }

      http.Response response;
      try {
        response = await _fetch(directUrl);
        if (response.statusCode == 404) {
          print('DataService: Direct endpoint 404, trying legacy...');
          response = await _fetch(legacyUrl);
        }
      } catch (e) {
        print('DataService: Direct endpoint error ($e), trying legacy...');
        response = await _fetch(legacyUrl);
      }

      print('DataService: Reviews response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final responseData = await compute(_parseJson, response.body);
        
        // Handle the actual API response structure
        List<dynamic> reviewsData;
        if (responseData.containsKey('reviews')) {
          reviewsData = responseData['reviews'] as List? ?? [];
        } else if (responseData is List) {
          reviewsData = responseData as List;
        } else {
          reviewsData = [];
        }

        // Sécurité: filtrer côté client si le backend renvoie trop large
        final filteredData = reviewsData.where((e) {
          if (e is Map<String, dynamic>) {
            final pid = e['professionalId'] ?? e['professionnelId'] ?? e['image'];
            return pid == professionnelId;
          }
          return false;
        }).toList();

        final reviews = filteredData.map((e) => Review.fromJson(e)).toList();
        print('DataService: Found ${reviews.length} reviews for professional $professionnelId (filtered client-side if needed)');
        
        return reviews;
      } else if (response.statusCode == 404) {
        // Aucun avis trouvé pour ce professionnel
        print('DataService: No reviews found for professional $professionnelId');
        return [];
      } else {
        print('DataService: Reviews fetch failed - Status: ${response.statusCode}');
        print('DataService: Response body: ${response.body}');
        throw Exception('Erreur lors de la récupération des avis: ${response.statusCode}');
      }
    } catch (e) {
      print('DataService: Exception during reviews fetch: $e');
      // En cas d'erreur réseau, retourner une liste vide plutôt que de planter
      if (e.toString().contains('Timeout') || e.toString().contains('network')) {
        print('DataService: Network error, returning empty reviews list');
        return [];
      }
      throw e;
    }
  }

  /// Génère des données simulées pour les tests de performance
  List<Professionnel> _generateSimulatedProfessionnels() {
    final stopwatch = Stopwatch()..start();
    
    final services = [
      'Comptable', 'Avocat', 'Notaire', 'Médecin', 'Dentiste', 'Pharmacien',
      'Ingénieur', 'Architecte', 'Plombier', 'Électricien', 'Mécanicien',
      'Coiffeur', 'Esthéticienne', 'Massothérapeute', 'Psychologue',
      'Nutritionniste', 'Kinésithérapeute', 'Ostéopathe', 'Chiropraticien',
      'Vétérinaire', 'Agent immobilier', 'Courtier hypothécaire', 'Banquier',
      'Assureur', 'Consultant', 'Traducteur', 'Photographe', 'Graphiste',
      'Développeur web', 'Marketeur', 'Professeur', 'Tuteur', 'Coach',
      'Personal trainer', 'Yoga instructor', 'Traiteur', 'Chef cuisinier',
      'Pâtissier', 'Fleuriste', 'Jardinier', 'Paysagiste', 'Peintre',
      'Menuisier', 'Maçon', 'Couvreur', 'Serrurier', 'Vitrier', 'Tapissier',
      'Décorateur', 'Organisateur d\'événements'
    ];

    final cities = [
      'Montréal', 'Québec', 'Laval', 'Gatineau', 'Longueuil', 'Sherbrooke',
      'Saguenay', 'Lévis', 'Trois-Rivières', 'Terrebonne', 'Saint-Jean-sur-Richelieu',
      'Repentigny', 'Boucherville', 'Saint-Jérôme', 'Drummondville',
      'Granby', 'Saint-Hyacinthe', 'Shawinigan', 'Dollard-des-Ormeaux',
      'Rimouski', 'Victoriaville', 'Thetford Mines', 'Saint-Georges',
      'Joliette', 'Sorel-Tracy', 'Vaudreuil-Dorion', 'Val-d\'Or',
      'Sept-Îles', 'Rouyn-Noranda', 'Alma', 'Rivière-du-Loup', 'Matane',
      'Chicoutimi', 'Baie-Comeau', 'Saint-Félicien', 'La Tuque',
      'Amos', 'Cowansville', 'Farnham', 'Magog', 'Greenfield Park',
      'Brossard', 'Saint-Lambert', 'Candiac', 'La Salle', 'Verdun'
    ];

    final firstNames = [
      'Marie', 'Jean', 'Pierre', 'Louise', 'Michel', 'Francine', 'Robert',
      'Diane', 'Alain', 'Sylvie', 'Claude', 'Nicole', 'Daniel', 'Lise',
      'André', 'Monique', 'Jacques', 'Ginette', 'Paul', 'Denise', 'François',
      'Suzanne', 'Gilles', 'Carole', 'Richard', 'Johanne', 'Marcel', 'Linda',
      'René', 'Céline', 'Yves', 'France', 'Bernard', 'Martine', 'Serge',
      'Chantal', 'Martin', 'Hélène', 'Normand', 'Julie', 'Réal', 'Nathalie'
    ];

    final lastNames = [
      'Tremblay', 'Gagnon', 'Roy', 'Côté', 'Bouchard', 'Gauthier', 'Morin',
      'Lavoie', 'Fortin', 'Gagné', 'Ouellet', 'Pelletier', 'Bélanger',
      'Lévesque', 'Bergeron', 'Leblanc', 'Paquette', 'Girard', 'Simard',
      'Boucher', 'Caron', 'Beaulieu', 'Cloutier', 'Dubé', 'Poirier',
      'Fournier', 'Lapointe', 'Leclerc', 'Lefebvre', 'Champagne', 'Boivin'
    ];

    final professionnels = <Professionnel>[];
    
    for (int i = 0; i < SIMULATION_PROFESSIONALS_COUNT; i++) {
      final firstName = firstNames[i % firstNames.length];
      final lastName = lastNames[i % lastNames.length];
      final service = services[i % services.length];
      final city = cities[i % cities.length];
      final isPremium = i % 10 == 0; // 10% premium
      
      final professionnel = Professionnel(
        id: 'sim_$i',
        title: '$firstName $lastName',
        subtitle: service,
        ville: city,
        address: '${100 + (i % 900)} Rue ${['Principale', 'Saint-Laurent', 'Sherbrooke', 'Bellevue'][i % 4]}, $city, QC',
        numroDeTlphone: '514-${(100 + i % 900).toString().padLeft(3, '0')}-${(1000 + i % 9000).toString()}',
        image: '',
        gallery: [],
        sousCategorie: service,
        plan: isPremium ? 'premium' : 'basic',
        averageRating: 3.0 + (i % 20) * 0.1, // Entre 3.0 et 5.0
        reviewCount: i % 50, // Entre 0 et 49
        email: '${firstName.toLowerCase()}.${lastName.toLowerCase()}@email.com',
        website: 'https://${firstName.toLowerCase()}${lastName.toLowerCase()}.com',
        isActive: true,
      );
      
      professionnels.add(professionnel);
    }
    
    stopwatch.stop();
    print('🧪 Génération de ${professionnels.length} professionnels simulés en ${stopwatch.elapsedMilliseconds}ms');
    
    return professionnels;
  }

  /// Génère des sous-catégories simulées pour les tests de performance
  List<SousCategorie> _generateSimulatedSousCategories() {
    final services = [
      'Comptable', 'Avocat', 'Notaire', 'Médecin', 'Dentiste', 'Pharmacien',
      'Ingénieur', 'Architecte', 'Plombier', 'Électricien', 'Mécanicien',
      'Coiffeur', 'Esthéticienne', 'Massothérapeute', 'Psychologue',
      'Nutritionniste', 'Kinésithérapeute', 'Ostéopathe', 'Chiropraticien',
      'Vétérinaire', 'Agent immobilier', 'Courtier hypothécaire', 'Banquier',
      'Assureur', 'Consultant', 'Traducteur', 'Photographe', 'Graphiste',
      'Développeur web', 'Marketeur', 'Professeur', 'Tuteur', 'Coach',
      'Personal trainer', 'Yoga instructor', 'Traiteur', 'Chef cuisinier',
      'Pâtissier', 'Fleuriste', 'Jardinier', 'Paysagiste', 'Peintre',
      'Menuisier', 'Maçon', 'Couvreur', 'Serrurier', 'Vitrier', 'Tapissier',
      'Décorateur', 'Organisateur d\'événements'
    ];

    final sousCategories = <SousCategorie>[];
    
    for (int i = 0; i < SIMULATION_SERVICES_COUNT && i < services.length; i++) {
      final service = services[i];
      final sousCategorie = SousCategorie(
        id: 'sim_cat_$i',
        title: service,
        titleEn: service, // Simplifié pour la simulation
        image: '',
        imageEn: '',
      );
      sousCategories.add(sousCategorie);
    }
    
    print('🧪 Génération de ${sousCategories.length} sous-catégories simulées');
    return sousCategories;
  }
}
