import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';

typedef AnalyticsLocaleProvider = String Function();

const int _eventVersion = 1;
const Duration _defaultRequestTimeout = Duration(seconds: 2);
const int _maxQueuedEvents = 100;
const List<Duration> _retryDelays = [
  Duration(milliseconds: 100),
  Duration(milliseconds: 250),
];
const Set<String> _allowedPlacements = {'directory', 'home_featured', 'detail'};
final RegExp _professionalIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

enum _SendResult { delivered, retryableFailure, terminalFailure }

/// Client first-party minimal pour mesurer la valeur apportée aux professionnels.
///
/// Le contrat est volontairement fermé : seules des dimensions agrégables et
/// non personnelles peuvent être envoyées. Les anciennes méthodes génériques
/// restent des no-op afin qu'aucun appel historique ne puisse contourner cette
/// liste blanche avec des paramètres arbitraires.
class FirebaseAnalyticsService {
  static final FirebaseAnalyticsService _instance =
      FirebaseAnalyticsService._internal();

  factory FirebaseAnalyticsService() => _instance;

  FirebaseAnalyticsService._internal()
    : this._(
        http.Client(),
        AppConfig.current.apiBaseUrl,
        _defaultRequestTimeout,
        _platformLocale,
        AppLogger.fromConfig(AppConfig.current),
        Random.secure(),
      );

  /// Construit une instance isolée dont le transport et l'URL sont injectables.
  /// Le client reste la propriété de l'appelant et n'est donc jamais fermé ici.
  FirebaseAnalyticsService.withClient(
    http.Client client, {
    required String baseUrl,
    Duration requestTimeout = _defaultRequestTimeout,
    AnalyticsLocaleProvider? localeProvider,
    AppLogger? logger,
  }) : this._(
         client,
         baseUrl,
         requestTimeout,
         localeProvider ?? _platformLocale,
         logger ?? AppLogger.fromConfig(AppConfig.current),
         Random.secure(),
       );

  FirebaseAnalyticsService._(
    this._client,
    String baseUrl,
    this._requestTimeout,
    this._localeProvider,
    this._logger,
    this._random,
  ) : _endpoint = _buildEndpoint(baseUrl);

  final http.Client _client;
  final Uri? _endpoint;
  final Duration _requestTimeout;
  final AnalyticsLocaleProvider _localeProvider;
  final AppLogger _logger;
  final Random _random;
  final List<Map<String, Object>> _pendingEvents = [];

  bool _isAvailable = false;
  bool _isDrainingQueue = false;
  String _currentLocale = 'fr';

  /// Active le transport seulement lorsque l'URL first-party est sûre.
  Future<void> initialize() async {
    try {
      _currentLocale = _normalizeLocale(_localeProvider()) ?? 'fr';
    } on Object {
      _currentLocale = 'fr';
    }
    _isAvailable = _endpoint != null && _requestTimeout > Duration.zero;
  }

  bool get isAvailable => _isAvailable;

  // API historique non business : no-op intentionnel.
  Future<void> logButtonTapped(
    String buttonName, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logPageView(
    String pageName, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logCustomEvent(
    String eventName,
    Map<String, Object> parameters,
  ) async {}

  Future<void> setUserProperty(String name, String? value) async {}

  Future<void> logUserEngagement(String actionType) async {}

  Future<void> logSearchEvent(
    String searchTerm, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logContactEvent(
    String contactType, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logLocationSearchEvent(
    String location, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logProfessionalViewEvent(
    String professionalId, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logAppOpenEvent({Map<String, Object>? parameters}) async {}

  Future<void> logScreenView(
    String screenName, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logFilterEvent(
    String filterType,
    String filterValue, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> logSortEvent(
    String sortType, {
    Map<String, Object>? parameters,
  }) async {}

  /// Met à jour la dimension locale sans créer d'événement de profilage.
  Future<void> logLanguageChange(
    String language, {
    Map<String, Object>? parameters,
  }) async {
    _rememberLocale(language);
  }

  Future<void> logErrorEvent(
    String errorType,
    String errorMessage, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> setCurrentScreen(
    String screenName, {
    Map<String, Object>? parameters,
  }) async {}

  Future<void> trackSponsorClick({
    String? sponsorId,
    String? sponsorName,
    String? categoryId,
    String? clickType,
    String? sourceScreen,
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackProfessionalEvent(
      type: 'professional_click',
      professionalId: sponsorId,
      placement: 'home_featured',
      locale: locale,
    );
  }

  Future<void> trackLanguageChange({
    String? language,
    String? fromLanguage,
    String? toLanguage,
    Map<String, Object>? parameters,
  }) async {
    _rememberLocale(toLanguage ?? language);
  }

  /// Conservée pour compatibilité. Aucun événement n'est émis tant que le
  /// contrat ROI ne définit pas une métrique de catégorie distincte.
  Future<void> trackCategoryView({
    String? category,
    String? categoryId,
    String? categoryName,
    String? categoryNameEn,
    String? sourceScreen,
    Map<String, Object>? parameters,
  }) async {}

  Future<void> trackSearch({
    String? query,
    String? searchQuery,
    String? searchType,
    int? resultsCount,
    String? locale,
    Map<String, Object>? parameters,
  }) {
    final safeResultsBucket = _resultsBucket(resultsCount);
    if (safeResultsBucket == null) return Future<void>.value();

    return _queueEvent({
      'type': 'search',
      'placement': 'directory',
      'searchKind': _searchKind(searchType),
      'resultsBucket': safeResultsBucket,
      'locale': _resolvedLocale(locale),
    });
  }

  Future<void> trackProfessionalView({
    String? professionalId,
    String? professionalName,
    String? categoryId,
    String? category,
    String? city,
    bool? isSponsor,
    String placement = 'detail',
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackProfessionalEvent(
      type: 'professional_view',
      professionalId: professionalId,
      placement: placement,
      locale: locale,
    );
  }

  Future<void> trackFavoriteAction({
    String? action,
    String? professionalId,
    String? professionalName,
    bool? isAdding,
    Map<String, Object>? parameters,
  }) async {}

  Future<void> trackPhoneCall({
    String? professionalId,
    String? professionalName,
    String? phoneNumber,
    String placement = 'detail',
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackContact(
      professionalId: professionalId,
      channel: 'phone',
      placement: placement,
      locale: locale,
    );
  }

  Future<void> trackMapNavigation({
    String? professionalId,
    String? professionalName,
    String? address,
    String placement = 'detail',
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackContact(
      professionalId: professionalId,
      channel: 'map',
      placement: placement,
      locale: locale,
    );
  }

  Future<void> trackWebsiteClick({
    String? professionalId,
    String? professionalName,
    String? website,
    String placement = 'detail',
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackContact(
      professionalId: professionalId,
      channel: 'website',
      placement: placement,
      locale: locale,
    );
  }

  Future<void> trackProfessionalImpression({
    required String professionalId,
    String? categoryId,
    required String placement,
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackProfessionalEvent(
      type: 'professional_impression',
      professionalId: professionalId,
      placement: placement,
      locale: locale,
    );
  }

  Future<void> trackCouponCopy({
    required String professionalId,
    String? categoryId,
    required String placement,
    String? locale,
    Map<String, Object>? parameters,
  }) {
    return _trackProfessionalEvent(
      type: 'coupon_copy',
      professionalId: professionalId,
      placement: placement,
      locale: locale,
    );
  }

  Future<void> _trackContact({
    required String? professionalId,
    required String channel,
    required String placement,
    String? locale,
  }) {
    return _trackProfessionalEvent(
      type: 'contact',
      professionalId: professionalId,
      placement: placement,
      channel: channel,
      locale: locale,
    );
  }

  Future<void> _trackProfessionalEvent({
    required String type,
    required String? professionalId,
    required String placement,
    String? channel,
    String? locale,
  }) {
    final safeProfessionalId = _normalizeProfessionalId(professionalId);
    final safePlacement = _normalizePlacement(placement);

    if (safeProfessionalId == null || safePlacement == null) {
      return Future<void>.value();
    }

    final dimensions = <String, Object>{
      'type': type,
      'professionalId': safeProfessionalId,
      'placement': safePlacement,
      'locale': _resolvedLocale(locale),
    };
    if (channel != null) dimensions['channel'] = channel;
    return _queueEvent(dimensions);
  }

  /// Programme l'envoi puis rend immédiatement la main au parcours UI.
  Future<void> _queueEvent(Map<String, Object> dimensions) {
    if (!_isAvailable || _endpoint == null) return Future<void>.value();

    try {
      final payload = <String, Object>{
        'version': _eventVersion,
        'eventId': _newEventId(),
        ...dimensions,
      };
      if (_pendingEvents.length >= _maxQueuedEvents) {
        _logFailure();
        return Future<void>.value();
      }
      _pendingEvents.add(payload);
      unawaited(_drainQueue());
    } on Object {
      _logFailure();
    }
    return Future<void>.value();
  }

  Future<void> _drainQueue() async {
    if (_isDrainingQueue) return;
    _isDrainingQueue = true;
    try {
      while (_pendingEvents.isNotEmpty) {
        final payload = _pendingEvents.first;
        final delivered = await _sendWithRetry(payload);
        _pendingEvents.removeAt(0);
        if (!delivered) _logFailure();
      }
    } finally {
      _isDrainingQueue = false;
      if (_pendingEvents.isNotEmpty) unawaited(_drainQueue());
    }
  }

  Future<bool> _sendWithRetry(Map<String, Object> payload) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_retryDelays[attempt - 1]);
      final result = await _sendOnce(payload);
      if (result == _SendResult.delivered) return true;
      if (result == _SendResult.terminalFailure) return false;
    }
    return false;
  }

  Future<_SendResult> _sendOnce(Map<String, Object> payload) async {
    try {
      final response = await _client
          .post(
            _endpoint!,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _SendResult.delivered;
      }
      if (response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500) {
        return _SendResult.retryableFailure;
      }
      return _SendResult.terminalFailure;
    } on Object {
      return _SendResult.retryableFailure;
    }
  }

  void _logFailure() {
    try {
      _logger.warning('Échec non bloquant de la télémétrie business.');
    } on Object {
      // Même un collecteur de journaux défaillant ne doit pas affecter l'UI.
    }
  }

  void _rememberLocale(String? locale) {
    final safeLocale = _normalizeLocale(locale);
    if (safeLocale != null) _currentLocale = safeLocale;
  }

  String _resolvedLocale(String? locale) {
    return _normalizeLocale(locale) ?? _currentLocale;
  }

  String _newEventId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

Uri? _buildEndpoint(String baseUrl) {
  final normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final baseUri = Uri.tryParse(normalizedBaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host.isEmpty ||
      baseUri.userInfo.isNotEmpty ||
      baseUri.hasQuery ||
      baseUri.hasFragment) {
    return null;
  }
  return Uri.parse('$normalizedBaseUrl/engagementEvent');
}

String _platformLocale() => PlatformDispatcher.instance.locale.languageCode;

String? _normalizeProfessionalId(String? value) {
  final normalized = value?.trim();
  if (normalized == null || !_professionalIdPattern.hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

String? _normalizePlacement(String? value) {
  final normalized = value?.trim().toLowerCase();
  return _allowedPlacements.contains(normalized) ? normalized : null;
}

String? _normalizeLocale(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll('-', '_');
  if (normalized == null) return null;
  if (normalized == 'fr' || normalized.startsWith('fr_')) return 'fr';
  if (normalized == 'en' || normalized.startsWith('en_')) return 'en';
  return null;
}

String _searchKind(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'city' => 'city',
    'category' => 'category',
    _ => 'text',
  };
}

String? _resultsBucket(int? count) {
  if (count == null || count < 0) return null;
  if (count == 0) return '0';
  if (count <= 5) return '1-5';
  if (count <= 20) return '6-20';
  return '21+';
}
