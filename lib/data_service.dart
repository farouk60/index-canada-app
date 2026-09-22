import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'models.dart';
import 'models/wix_partner_models.dart';
import 'models/wix_offer_models.dart';

// Fonction de premier niveau requise par compute().
Object? _parseJson(String jsonString) {
  return json.decode(jsonString);
}

final AppLogger _dataLogger = AppLogger.fromConfig(AppConfig.current);

void _debugLog(String message) => _dataLogger.debug(message);

class DataService {
  static final String _functionsBaseUrl = AppConfig.current.apiBaseUrl
      .replaceFirst(RegExp(r'/+$'), '');
  static final String baseUrl = '$_functionsBaseUrl/data';

  // Singleton pattern pour éviter les instances multiples
  static final DataService _instance = DataService._internal(http.Client());
  factory DataService() => _instance;
  DataService._internal(this._client);

  @visibleForTesting
  DataService.withClient(http.Client client) : _client = client;

  final http.Client _client;

  // Cache local avec expiration pour optimiser Wix
  Map<String, dynamic>? _cachedData;

  // Une même requête réseau est partagée entre les consommateurs concurrents.
  Future<Map<String, dynamic>>? _pendingRequest;

  // Les nouvelles routes Wix v2 sont mises en cache indépendamment selon leurs
  // filtres. Les requêtes identiques en cours partagent aussi le même Future.
  final Map<String, List<Map<String, dynamic>>> _directoryCache = {};
  final Map<String, Future<List<Map<String, dynamic>>>>
  _pendingDirectoryRequests = {};
  String? _directoryRefreshToken;
  int _cacheGeneration = 0;

  /// Vide le cache pour forcer le rechargement des données
  void clearCache() {
    _cacheGeneration++;
    _cachedData = null;
    _pendingRequest = null;
    _directoryCache.clear();
    _pendingDirectoryRequests.clear();
    _directoryRefreshToken = null;
    _debugLog('🗑️ Cache DataService vidé');
  }

  /// Invalide les caches avant une lecture fraîche des routes Wix ciblées.
  Future<void> forceSyncWithWix() {
    _debugLog('🔄 PRÉPARATION D’UNE ACTUALISATION WIX');
    clearCache();
    _directoryRefreshToken = DateTime.now().microsecondsSinceEpoch.toString();
    return Future<void>.value();
  }

  Future<Map<String, dynamic>> fetchAllData() async {
    // Si on a déjà une requête en cours, on la partage
    if (_pendingRequest != null) {
      _debugLog('✅ Requête en cours détectée, attente de la réponse partagée');
      return _pendingRequest!;
    }

    // Vérifier le cache en premier
    if (_cachedData != null) {
      _debugLog('✅ Données servies depuis le cache');
      return _cachedData!;
    }

    return await _fetchAllData(forceRefresh: false);
  }

  /// Méthode privée pour récupérer les données depuis l'API
  Future<Map<String, dynamic>> _fetchAllData({
    bool forceRefresh = false,
  }) async {
    // Même un rafraîchissement forcé rejoint la requête déjà active afin de ne
    // jamais lancer deux lectures concurrentes vers le backend.
    final activeRequest = _pendingRequest;
    if (activeRequest != null) {
      return activeRequest;
    }

    if (!forceRefresh && _cachedData != null) {
      return _cachedData!;
    }

    final request = _requestAllData(
      forceRefresh: forceRefresh,
      generation: _cacheGeneration,
    );
    _pendingRequest = request;

    try {
      return await request;
    } finally {
      if (identical(_pendingRequest, request)) {
        _pendingRequest = null;
      }
    }
  }

  Future<Map<String, dynamic>> _requestAllData({
    required bool forceRefresh,
    required int generation,
  }) async {
    try {
      _debugLog('🌐 Récupération des données depuis Wix...');

      final url = forceRefresh
          ? Uri.parse(baseUrl).replace(
              queryParameters: {
                'refresh': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            )
          : Uri.parse(baseUrl);
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));

      _debugLog('DataService: Response status: ${response.statusCode}');
      _debugLog(
        'DataService: Response length: ${response.body.length} characters',
      );

      if (response.statusCode != 200) {
        throw http.ClientException(
          'Réponse HTTP inattendue (${response.statusCode})',
          url,
        );
      }

      final decoded = await compute(_parseJson, response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Réponse de données invalide');
      }

      if (generation == _cacheGeneration) {
        _cachedData = decoded;
      }
      _debugLog('✅ Données récupérées et mises en cache avec succès');
      return decoded;
    } catch (error) {
      _debugLog('❌ Erreur lors de la récupération des données: $error');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDirectoryItems({
    required String path,
    required String responseKey,
    Map<String, String> query = const {},
    required int maxItems,
    bool forceRefresh = false,
  }) {
    final normalizedQuery = Map<String, String>.fromEntries(
      query.entries
          .where((entry) => entry.value.trim().isNotEmpty)
          .map((entry) => MapEntry(entry.key, entry.value.trim())),
    );
    final cacheKey = Uri(
      path: path,
      queryParameters: normalizedQuery.isEmpty ? null : normalizedQuery,
    ).toString();

    if (forceRefresh) {
      _directoryCache.remove(cacheKey);
      _pendingDirectoryRequests.remove(cacheKey);
    } else {
      final cached = _directoryCache[cacheKey];
      if (cached != null) return Future.value(cached);
      final pending = _pendingDirectoryRequests[cacheKey];
      if (pending != null) return pending;
    }

    final generation = _cacheGeneration;
    final refreshToken = forceRefresh
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : _directoryRefreshToken;
    final request = _requestDirectoryItems(
      path: path,
      responseKey: responseKey,
      query: normalizedQuery,
      maxItems: maxItems,
      refreshToken: refreshToken,
    );
    _pendingDirectoryRequests[cacheKey] = request;

    return request
        .then((items) {
          if (generation == _cacheGeneration &&
              identical(_pendingDirectoryRequests[cacheKey], request)) {
            _directoryCache[cacheKey] = items;
          }
          return items;
        })
        .whenComplete(() {
          if (identical(_pendingDirectoryRequests[cacheKey], request)) {
            _pendingDirectoryRequests.remove(cacheKey);
          }
        });
  }

  Future<List<Map<String, dynamic>>> _requestDirectoryItems({
    required String path,
    required String responseKey,
    required Map<String, String> query,
    required int maxItems,
    String? refreshToken,
  }) async {
    const pageSize = 100;
    final allItems = <Map<String, dynamic>>[];
    final seenCursors = <String>{};
    final seenItemIds = <String>{};
    final maxPages = (maxItems / pageSize).ceil() + 1;
    var pageCount = 0;
    String? cursor;

    while (true) {
      pageCount++;
      if (pageCount > maxPages) {
        throw FormatException('Pagination $responseKey trop longue');
      }
      final queryParameters = <String, String>{
        ...query,
        'limit': '$pageSize',
        'cursor': ?cursor,
        'refresh': ?refreshToken,
      };
      final url = Uri.parse('$_functionsBaseUrl/$path')
          .replace(queryParameters: queryParameters);
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw http.ClientException(
          'Réponse HTTP inattendue (${response.statusCode})',
          url,
        );
      }

      final decoded = await compute(_parseJson, response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['version'] != 2) {
        throw const FormatException('Réponse de répertoire invalide');
      }

      final rawItems = decoded[responseKey];
      if (rawItems is! List) {
        throw FormatException('Collection $responseKey invalide');
      }
      for (final item in rawItems) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('Élément $responseKey invalide');
        }
        final itemId = item['_id'];
        if (itemId is! String || itemId.isEmpty || !seenItemIds.add(itemId)) {
          throw FormatException(
            'Identifiant $responseKey invalide ou dupliqué',
          );
        }
        allItems.add(item);
      }
      if (allItems.length > maxItems) {
        throw FormatException('Collection $responseKey trop volumineuse');
      }

      final pagination = decoded['pagination'];
      if (pagination is! Map<String, dynamic> ||
          pagination['has_more'] is! bool) {
        throw const FormatException('Pagination de répertoire invalide');
      }
      final hasMore = pagination['has_more'] as bool;
      final nextCursor = pagination['next_cursor'];
      if (!hasMore) {
        cursor = null;
        break;
      }
      if (nextCursor is! String ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        throw const FormatException('Curseur de pagination invalide');
      }
      cursor = nextCursor;
    }

    return List<Map<String, dynamic>>.unmodifiable(allItems);
  }

  Future<List<SousCategorie>> fetchSousCategories({
    bool forceRefresh = false,
  }) async {
    _debugLog('DataService: fetchSousCategories called');

    try {
      final items = await _fetchDirectoryItems(
        path: 'categories',
        responseKey: 'categories',
        maxItems: 2000,
        forceRefresh: forceRefresh,
      );
      _debugLog(
        'DataService: Processing ${items.length} sous-categories items',
      );

      final sousCategories = <SousCategorie>[];
      for (int i = 0; i < items.length; i++) {
        try {
          final sousCategorie = SousCategorie.fromJson(items[i]);
          sousCategories.add(sousCategorie);
        } catch (e) {
          _debugLog('DataService: Error processing sous-categorie $i: $e');
          // Continue avec les autres sous-catégories
        }
      }

      return sousCategories;
    } catch (e) {
      _debugLog('DataService: Error in fetchSousCategories: $e');
      rethrow;
    }
  }

  Future<List<Professionnel>> fetchSponsoredProfessionnels({
    bool forceRefresh = false,
  }) async {
    _debugLog('DataService: fetchSponsoredProfessionnels called');

    try {
      final items = await _fetchDirectoryItems(
        path: 'professionals',
        responseKey: 'professionals',
        query: const {'featured': 'true'},
        maxItems: 10000,
        forceRefresh: forceRefresh,
      );
      _debugLog(
        'DataService: Processing ${items.length} featured professionals',
      );

      final sponsoredProfessionals = <Professionnel>[];
      for (int i = 0; i < items.length; i++) {
        try {
          sponsoredProfessionals.add(Professionnel.fromJson(items[i]));
        } catch (e) {
          _debugLog('DataService: Error processing professional $i: $e');
        }
      }

      _debugLog(
        'DataService: Found ${sponsoredProfessionals.length} featured professionnels',
      );
      return sponsoredProfessionals;
    } catch (e) {
      _debugLog('DataService: Error in fetchSponsoredProfessionnels: $e');
      rethrow;
    }
  }

  Future<List<Professionnel>> fetchProfessionnels({
    String? sousCategorie,
    String? search,
    String? ville,
    bool forceRefresh = false,
  }) async {
    final items = await _fetchDirectoryItems(
      path: 'professionals',
      responseKey: 'professionals',
      query: {'category': ?sousCategorie, 'search': ?search, 'city': ?ville},
      maxItems: 10000,
      forceRefresh: forceRefresh,
    );
    final allProfessionnels = <Professionnel>[];
    for (var index = 0; index < items.length; index++) {
      try {
        allProfessionnels.add(Professionnel.fromJson(items[index]));
      } catch (error) {
        _debugLog(
          'DataService: professionnel invalide ignoré à l’index $index: $error',
        );
      }
    }

    // La route applique les filtres côté Wix. Le tri local conserve l'ordre
    // historique en donnant la priorité aux profils premium.
    allProfessionnels.sort((a, b) {
      if (a.plan.toLowerCase() == 'premium' &&
          b.plan.toLowerCase() != 'premium') {
        return -1;
      }
      if (a.plan.toLowerCase() != 'premium' &&
          b.plan.toLowerCase() == 'premium') {
        return 1;
      }
      return 0;
    });

    _debugLog('DataService: ${allProfessionnels.length} professionnels reçus');
    return allProfessionnels;
  }

  /// Charge uniquement les professionnels favoris, par lots Wix de 50 IDs.
  Future<List<Professionnel>> fetchProfessionnelsByIds(
    List<String> ids, {
    bool forceRefresh = false,
  }) async {
    final validId = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
    final normalizedIds = ids
        .map((id) => id.trim())
        .where(validId.hasMatch)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) return const [];

    final professionalsById = <String, Professionnel>{};
    for (var start = 0; start < normalizedIds.length; start += 50) {
      final end = start + 50 < normalizedIds.length
          ? start + 50
          : normalizedIds.length;
      final batch = normalizedIds.sublist(start, end);
      final items = await _fetchDirectoryItems(
        path: 'professionals',
        responseKey: 'professionals',
        query: {'ids': batch.join(',')},
        maxItems: 50,
        forceRefresh: forceRefresh,
      );
      for (final item in items) {
        final professional = Professionnel.fromJson(item);
        if (professional.id.isNotEmpty) {
          professionalsById[professional.id] = professional;
        }
      }
    }

    return normalizedIds
        .map((id) => professionalsById[id])
        .whereType<Professionnel>()
        .toList(growable: false);
  }

  Future<List<WixPartner>> fetchPartners({bool forceRefresh = false}) async {
    _debugLog(
      'DataService: fetchPartners called with forceRefresh: $forceRefresh',
    );

    final items = await _fetchDirectoryItems(
      path: 'partners',
      responseKey: 'partners',
      maxItems: 2000,
      forceRefresh: forceRefresh,
    );

    try {
      _debugLog(
        'DataService: Processing ${items.length} partners from Wix collection',
      );
      var partners = items.map(WixPartner.fromJson).toList();
      // Filtrer ceux qui doivent être affichés
      partners = partners.where((p) => p.shouldDisplay).toList();
      // Trier: d'abord en vedette, puis par ordre d'affichage, puis par titre
      partners.sort((a, b) {
        final featuredCmp = (b.isFeatured ? 1 : 0).compareTo(
          a.isFeatured ? 1 : 0,
        );
        if (featuredCmp != 0) return featuredCmp;
        final orderCmp = a.displayOrder.compareTo(b.displayOrder);
        if (orderCmp != 0) return orderCmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      return partners;
    } catch (e) {
      _debugLog('DataService: Error parsing partners: $e');
      rethrow;
    }
  }

  Future<List<WixOffer>> fetchOffers({bool forceRefresh = false}) async {
    _debugLog(
      'DataService: fetchOffers called with forceRefresh: $forceRefresh',
    );

    final items = await _fetchDirectoryItems(
      path: 'offers',
      responseKey: 'offers',
      maxItems: 2000,
      forceRefresh: forceRefresh,
    );

    try {
      _debugLog(
        'DataService: Processing ${items.length} offers from Wix collection',
      );
      return items.map(WixOffer.fromWixData).toList();
    } catch (e) {
      _debugLog('DataService: Error parsing offers: $e');
      rethrow;
    }
  }

  Future<List<WixOffer>> fetchValidOffers({bool forceRefresh = false}) async {
    final allOffers = await fetchOffers(forceRefresh: forceRefresh);
    return allOffers.where((offer) => offer.isValid).toList();
  }

  Future<List<WixOffer>> fetchExclusiveOffers({
    bool forceRefresh = false,
  }) async {
    final allOffers = await fetchOffers(forceRefresh: forceRefresh);
    return allOffers
        .where((offer) => offer.isValid && offer.isExclusive)
        .toList();
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
      _debugLog('DataService: Error in searchAll: $e');
      rethrow;
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
    try {
      // Préparer les données selon la structure de votre collection Wix Reviews
      final reviewData = {
        'professionnelId': professionnelId, // ID du champ: professionnelId
        'auteurNom': name, // ID du champ: auteurNom
        'rating': rating, // ID du champ: rating
        'message': message, // ID du champ: message
        'title': title, // ID du champ: title
        'dateCreation': DateTime.now()
            .toIso8601String(), // ID du champ: dateCreation
      };

      // Endpoint pour l'enregistrement d'avis
      // Utilise directement la fonction Wix "post_review" exposée à /_functions/review
      // pour éviter le routeur legacy /_functions/data qui exige encore email/phone.
      final url = Uri.parse('$_functionsBaseUrl/review');

      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(reviewData),
          )
          .timeout(const Duration(seconds: 15));

      _debugLog(
        'DataService: Review post response status: ${response.statusCode}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _debugLog('DataService: Review posted successfully');

        // Vider le cache pour forcer un rechargement
        clearCache();
      } else {
        _debugLog(
          'DataService: Review post failed - Status: ${response.statusCode}',
        );
        throw Exception(
          'Erreur lors de l\'enregistrement de l\'avis: ${response.statusCode}',
        );
      }
    } catch (e) {
      _debugLog('DataService: Exception during review post: $e');
      rethrow;
    }
  }

  /// Récupère les avis pour un professionnel spécifique
  Future<List<Review>> fetchReviews(
    String professionnelId, {
    bool forceRefresh = false,
  }) async {
    try {
      final rawReviews = await _fetchDirectoryItems(
        path: 'reviews',
        responseKey: 'reviews',
        query: {'professionalId': professionnelId},
        maxItems: 10000,
        forceRefresh: forceRefresh,
      );

      // La route v2 ne projette que les avis approuvés. Le contrôle d'ID reste
      // une défense côté client contre une réponse backend incohérente.
      final reviews = rawReviews
          .where((review) => review['professionalId'] == professionnelId)
          .map(Review.fromJson)
          .toList(growable: false);
      _debugLog('DataService: ${reviews.length} avis valides chargés');
      return reviews;
    } on TimeoutException {
      _debugLog('DataService: délai dépassé lors du chargement des avis');
      rethrow;
    } on http.ClientException {
      _debugLog('DataService: réseau indisponible lors du chargement des avis');
      rethrow;
    } catch (_) {
      rethrow;
    }
  }
}
