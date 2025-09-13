// Firebase Analytics Service Stub (disabled for privacy compliance)
class FirebaseAnalyticsService {
  static final FirebaseAnalyticsService _instance =
      FirebaseAnalyticsService._internal();
  factory FirebaseAnalyticsService() => _instance;
  FirebaseAnalyticsService._internal();

  bool _isInitialized = false;

  /// Initialise Firebase Analytics (disabled)
  Future<void> initialize() async {
    try {
      _isInitialized = true;
      print('Firebase Analytics désactivé pour la conformité de confidentialité');
    } catch (e) {
      print('Erreur lors de l\'initialisation de Firebase Analytics: $e');
    }
  }

  /// Vérifie si Analytics est disponible (always false)
  bool get isAvailable => false;

  // Complete stub methods for all Firebase Analytics events
  Future<void> logButtonTapped(String buttonName, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logPageView(String pageName, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logCustomEvent(String eventName, Map<String, Object> parameters) async {
    // No-op
  }

  Future<void> setUserProperty(String name, String? value) async {
    // No-op
  }

  Future<void> logUserEngagement(String actionType) async {
    // No-op
  }

  Future<void> logSearchEvent(String searchTerm, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logContactEvent(String contactType, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logLocationSearchEvent(String location, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logProfessionalViewEvent(String professionalId, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logAppOpenEvent({Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logScreenView(String screenName, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logFilterEvent(String filterType, String filterValue, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logSortEvent(String sortType, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logLanguageChange(String language, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> logErrorEvent(String errorType, String errorMessage, {Map<String, Object>? parameters}) async {
    // No-op
  }

  // Additional methods that the app uses - all with comprehensive parameters
  Future<void> setCurrentScreen(String screenName, {Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackSponsorClick({String? sponsorId, String? sponsorName, String? clickType, String? sourceScreen, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackLanguageChange({String? language, String? fromLanguage, String? toLanguage, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackCategoryView({String? category, String? categoryId, String? categoryName, String? categoryNameEn, String? sourceScreen, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackSearch({String? query, String? searchQuery, String? searchType, int? resultsCount, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackProfessionalView({String? professionalId, String? professionalName, String? categoryId, String? category, String? city, bool? isSponsor, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackFavoriteAction({String? action, String? professionalId, String? professionalName, bool? isAdding, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackPhoneCall({String? professionalId, String? professionalName, String? phoneNumber, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackMapNavigation({String? professionalId, String? professionalName, String? address, Map<String, Object>? parameters}) async {
    // No-op
  }

  Future<void> trackWebsiteClick({String? professionalId, String? professionalName, String? website, Map<String, Object>? parameters}) async {
    // No-op
  }
}
