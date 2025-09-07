import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseAnalyticsService {
  static final FirebaseAnalyticsService _instance =
      FirebaseAnalyticsService._internal();
  factory FirebaseAnalyticsService() => _instance;
  FirebaseAnalyticsService._internal();

  FirebaseAnalytics? _analytics;
  bool _isInitialized = false;

  /// Initialise Firebase Analytics
  Future<void> initialize() async {
    try {
      if (!_isInitialized) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        _analytics = FirebaseAnalytics.instance;
        _isInitialized = true;
        print('Firebase Analytics initialisé avec succès');
      }
    } catch (e) {
      print('Erreur lors de l\'initialisation de Firebase Analytics: $e');
    }
  }

  /// Vérifie si Analytics est disponible
  bool get isAvailable => _isInitialized && _analytics != null;

  // ============================================================================
  // MÉTRIQUES SPÉCIFIQUES DEMANDÉES
  // ============================================================================

  /// 1. Nombre de visites par fiche pro
  Future<void> trackProfessionalView({
    required String professionalId,
    required String professionalName,
    required String category,
    required String city,
    bool isSponsor = false,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'professional_view',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'category': category,
          'city': city,
          'is_sponsor': isSponsor ? 'true' : 'false',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      print('📊 Vue professionnel trackée: $professionalName');
    } catch (e) {
      print('Erreur tracking vue professionnel: $e');
    }
  }

  /// 2. Taux de clic sur les sponsors
  Future<void> trackSponsorClick({
    required String sponsorId,
    required String sponsorName,
    required String clickType, // 'card', 'carousel', 'detail_button'
    String? sourceScreen,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'sponsor_click',
        parameters: {
          'sponsor_id': sponsorId,
          'sponsor_name': sponsorName,
          'click_type': clickType,
          'source_screen': sourceScreen ?? 'unknown',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      print('🎯 Clic sponsor tracké: $sponsorName ($clickType)');
    } catch (e) {
      print('Erreur tracking clic sponsor: $e');
    }
  }

  /// 3. Catégories les plus consultées
  Future<void> trackCategoryView({
    required String categoryId,
    required String categoryName,
    required String categoryNameEn,
    String? sourceScreen,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'category_view',
        parameters: {
          'category_id': categoryId,
          'category_name': categoryName,
          'category_name_en': categoryNameEn,
          'source_screen': sourceScreen ?? 'services_page',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      print('📂 Catégorie trackée: $categoryName');
    } catch (e) {
      print('Erreur tracking catégorie: $e');
    }
  }

  // ============================================================================
  // MÉTRIQUES COMPLÉMENTAIRES UTILES
  // ============================================================================

  /// Recherche effectuée
  Future<void> trackSearch({
    required String searchQuery,
    required String searchType, // 'professional', 'city', 'category'
    required int resultsCount,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'search_performed',
        parameters: {
          'search_query': searchQuery,
          'search_type': searchType,
          'results_count': resultsCount,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking recherche: $e');
    }
  }

  /// Appel téléphonique lancé
  Future<void> trackPhoneCall({
    required String professionalId,
    required String professionalName,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'phone_call_initiated',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking appel: $e');
    }
  }

  /// Ouverture de carte/navigation
  Future<void> trackMapNavigation({
    required String professionalId,
    required String professionalName,
    required String address,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'map_navigation',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'address': address,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking navigation: $e');
    }
  }

  /// Ouverture du site web du professionnel
  Future<void> trackWebsiteClick({
    required String professionalId,
    required String professionalName,
    required String website,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'website_click',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'website': website,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking site web: $e');
    }
  }

  /// Ajout/suppression de favori
  Future<void> trackFavoriteAction({
    required String professionalId,
    required String professionalName,
    required bool isAdding, // true = ajout, false = suppression
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'favorite_action',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'action': isAdding ? 'add' : 'remove',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking favori: $e');
    }
  }

  /// Consultation de galerie d'images
  Future<void> trackGalleryView({
    required String professionalId,
    required String professionalName,
    required int imageCount,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'gallery_view',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'image_count': imageCount,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking galerie: $e');
    }
  }

  /// Utilisation d'un coupon
  Future<void> trackCouponView({
    required String professionalId,
    required String professionalName,
    required String couponCode,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'coupon_view',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'coupon_code': couponCode,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking coupon: $e');
    }
  }

  /// Ajout d'un avis
  Future<void> trackReviewSubmission({
    required String professionalId,
    required String professionalName,
    required int rating,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'review_submitted',
        parameters: {
          'professional_id': professionalId,
          'professional_name': professionalName,
          'rating': rating,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking avis: $e');
    }
  }

  /// Changement de langue
  Future<void> trackLanguageChange({
    required String fromLanguage,
    required String toLanguage,
  }) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logEvent(
        name: 'language_changed',
        parameters: {
          'from_language': fromLanguage,
          'to_language': toLanguage,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      print('Erreur tracking langue: $e');
    }
  }

  // ============================================================================
  // MÉTRIQUES D'ÉCRAN
  // ============================================================================

  /// Définir l'écran actuel
  Future<void> setCurrentScreen(String screenName) async {
    if (!isAvailable) return;

    try {
      await _analytics!.logScreenView(
        screenName: screenName,
        screenClass: screenName,
      );
    } catch (e) {
      print('Erreur définition écran: $e');
    }
  }

  /// Définir des propriétés utilisateur
  Future<void> setUserProperties({
    String? preferredLanguage,
    String? userRegion,
  }) async {
    if (!isAvailable) return;

    try {
      if (preferredLanguage != null) {
        await _analytics!.setUserProperty(
          name: 'preferred_language',
          value: preferredLanguage,
        );
      }
      if (userRegion != null) {
        await _analytics!.setUserProperty(
          name: 'user_region',
          value: userRegion,
        );
      }
    } catch (e) {
      print('Erreur propriétés utilisateur: $e');
    }
  }
}
