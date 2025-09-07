import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wix_partner_models.dart';
import '../utils/string_utils.dart';

/// Service pour récupérer les partenaires depuis Wix
class WixPartnerService {
  static final WixPartnerService _instance = WixPartnerService._internal();
  factory WixPartnerService() => _instance;
  WixPartnerService._internal();

  static const String baseUrl =
      'https://www.immigrantindex.com/_functions/data';

  // Cache local
  Map<String, dynamic>? _cachedPartnersData;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidityDuration = Duration(minutes: 10);

  /// Vide le cache pour forcer le rechargement
  void clearCache() {
    _cachedPartnersData = null;
    _lastFetchTime = null;
  }

  /// Vérifie si le cache est encore valide
  bool get _isCacheValid {
    if (_cachedPartnersData == null || _lastFetchTime == null) return false;
    return DateTime.now().difference(_lastFetchTime!) < _cacheValidityDuration;
  }

  /// Récupère tous les partenaires depuis Wix
  Future<List<WixPartner>> fetchPartners({bool forceRefresh = false}) async {
    print(
      'WixPartnerService: fetchPartners called with forceRefresh: $forceRefresh',
    );

    // Utiliser le cache si valide et pas de force refresh
    if (!forceRefresh && _isCacheValid) {
      print('WixPartnerService: Using cached data');
      return _parsePartnersFromCache();
    }

    try {
      print('WixPartnerService: Fetching partners from server...');

      // Ajouter un timestamp pour éviter le cache côté serveur
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$baseUrl?t=$timestamp');

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Timeout: La requête a pris trop de temps');
            },
          );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Mise à jour du cache
        _cachedPartnersData = data;
        _lastFetchTime = DateTime.now();

        return _parsePartners(data);
      } else {
        throw Exception('Erreur HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur lors de la récupération des partenaires: $e');

      // Essayer d'utiliser le cache en cas d'erreur réseau
      if (_cachedPartnersData != null) {
        print('📱 Utilisation des données en cache suite à l\'erreur');
        return _parsePartnersFromCache();
      }

      throw Exception('Impossible de récupérer les partenaires: $e');
    }
  }

  /// Parse les partenaires depuis les données en cache
  List<WixPartner> _parsePartnersFromCache() {
    if (_cachedPartnersData == null) return [];
    return _parsePartners(_cachedPartnersData!);
  }

  /// Parse les partenaires depuis les données reçues
  List<WixPartner> _parsePartners(Map<String, dynamic> data) {
    try {
      // Chercher la clé 'partners' ou 'partenaires' dans les données
      List<dynamic>? partnersJson;

      if (data.containsKey('partners')) {
        partnersJson = data['partners'] as List<dynamic>?;
      } else if (data.containsKey('partenaires')) {
        partnersJson = data['partenaires'] as List<dynamic>?;
      }

      if (partnersJson == null) {
        print('⚠️ Aucune donnée de partenaires trouvée dans la réponse');
        return [];
      }

      final partners = partnersJson
          .map((json) => WixPartner.fromJson(json as Map<String, dynamic>))
          .where((partner) => partner.shouldDisplay) // Filtrer les inactifs
          .toList();

      // Trier par ordre d'affichage, puis par nom
      partners.sort((a, b) {
        // D'abord par ordre d'affichage
        int orderComparison = a.displayOrder.compareTo(b.displayOrder);
        if (orderComparison != 0) return orderComparison;

        // Puis les en vedette en premier
        if (a.isFeatured && !b.isFeatured) return -1;
        if (!a.isFeatured && b.isFeatured) return 1;

        // Enfin par nom alphabétique
        return normalizeForSorting(
          a.title,
        ).compareTo(normalizeForSorting(b.title));
      });

      print('✅ ${partners.length} partenaires récupérés et triés');
      return partners;
    } catch (e) {
      print('❌ Erreur lors du parsing des partenaires: $e');
      return [];
    }
  }

  /// Récupère les partenaires en vedette seulement
  Future<List<WixPartner>> fetchFeaturedPartners({
    bool forceRefresh = false,
  }) async {
    final allPartners = await fetchPartners(forceRefresh: forceRefresh);
    return allPartners.where((partner) => partner.isActiveFeatured).toList();
  }

  /// Récupère les partenaires par catégorie
  Future<List<WixPartner>> fetchPartnersByCategory(
    String category, {
    bool forceRefresh = false,
  }) async {
    final allPartners = await fetchPartners(forceRefresh: forceRefresh);
    return allPartners
        .where(
          (partner) => partner.category.toLowerCase() == category.toLowerCase(),
        )
        .toList();
  }

  /// Récupère les catégories disponibles
  Future<List<String>> getAvailableCategories({
    bool forceRefresh = false,
  }) async {
    final allPartners = await fetchPartners(forceRefresh: forceRefresh);
    final categories = allPartners
        .map((partner) => partner.category)
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();

    categories.sort();
    return categories;
  }

  /// Recherche de partenaires par nom
  Future<List<WixPartner>> searchPartners(
    String query, {
    bool forceRefresh = false,
  }) async {
    if (query.isEmpty) return [];

    final allPartners = await fetchPartners(forceRefresh: forceRefresh);
    final lowerQuery = query.toLowerCase();

    return allPartners.where((partner) {
      return partner.title.toLowerCase().contains(lowerQuery) ||
          partner.titleEn.toLowerCase().contains(lowerQuery) ||
          partner.description.toLowerCase().contains(lowerQuery) ||
          partner.descriptionEn.toLowerCase().contains(lowerQuery) ||
          partner.category.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Récupère un partenaire par ID
  Future<WixPartner?> getPartnerById(String id) async {
    final allPartners = await fetchPartners();
    try {
      return allPartners.firstWhere((partner) => partner.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Obtient les statistiques des partenaires
  Future<Map<String, int>> getPartnerStats() async {
    final allPartners = await fetchPartners();

    return {
      'total': allPartners.length,
      'active': allPartners.where((p) => p.isActive).length,
      'featured': allPartners.where((p) => p.isActiveFeatured).length,
      'official': allPartners.where((p) => p.isOfficial).length,
      'categories': allPartners.map((p) => p.category).toSet().length,
    };
  }
}
