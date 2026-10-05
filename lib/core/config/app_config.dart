import 'package:flutter/foundation.dart';

/// Signale une configuration de livraison incohérente avant que l'interface
/// ou un module natif ne soit initialisé.
final class AppConfigurationException implements Exception {
  const AppConfigurationException(this.issues);

  final List<String> issues;

  @override
  String toString() => 'AppConfigurationException(${issues.join(', ')})';
}

/// Environnement d'exécution de l'application.
enum AppEnvironment {
  development,
  staging,
  production;

  static AppEnvironment fromName(String value) {
    return switch (value.trim().toLowerCase()) {
      'development' || 'dev' => AppEnvironment.development,
      'staging' || 'stage' => AppEnvironment.staging,
      _ => AppEnvironment.production,
    };
  }
}

/// Configuration immuable lue au démarrage depuis les `--dart-define`.
@immutable
final class AppConfig {
  static const productionApiBaseUrl =
      'https://www.immigrantindex.com/_functions';
  static const _stagingApiScheme = 'https';
  static const _stagingApiHost = 'immigrantindex.wixsite.com';
  static const _stagingApiPath = '/website-1/_functions';

  const AppConfig({
    required this.environment,
    required this.appName,
    required this.apiBaseUrl,
    required this.imageCacheMaximumSize,
    required this.imageCacheMaximumSizeBytes,
    required this.loggingEnabled,
  });

  factory AppConfig.fromEnvironment() {
    const environmentName = String.fromEnvironment(
      'APP_ENVIRONMENT',
      defaultValue: 'production',
    );

    return AppConfig(
      environment: AppEnvironment.fromName(environmentName),
      appName: const String.fromEnvironment(
        'APP_NAME',
        defaultValue: 'Index Canada',
      ),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: productionApiBaseUrl,
      ),
      imageCacheMaximumSize: const int.fromEnvironment(
        'IMAGE_CACHE_MAXIMUM_SIZE',
        defaultValue: 200,
      ),
      imageCacheMaximumSizeBytes: const int.fromEnvironment(
        'IMAGE_CACHE_MAXIMUM_SIZE_BYTES',
        defaultValue: 50 * 1024 * 1024,
      ),
      loggingEnabled: const bool.fromEnvironment(
        'ENABLE_DEBUG_LOGGING',
        defaultValue: !kReleaseMode,
      ),
    );
  }

  static final AppConfig current = AppConfig.fromEnvironment();

  final AppEnvironment environment;
  final String appName;
  final String apiBaseUrl;
  final int imageCacheMaximumSize;
  final int imageCacheMaximumSizeBytes;
  final bool loggingEnabled;

  /// Vérifie les invariants qui doivent être vrais dans toute livraison.
  ///
  /// Stripe est volontairement absent de ces invariants : une livraison
  /// mobile ne doit ni exiger ni initialiser une clé Stripe.
  List<String> validationIssues() {
    final issues = <String>[];
    final apiUri = Uri.tryParse(apiBaseUrl.trim());

    if (appName.trim().isEmpty) {
      issues.add('APP_NAME_EMPTY');
    }
    if (apiUri == null ||
        apiBaseUrl != apiBaseUrl.trim() ||
        apiUri.scheme != 'https' ||
        apiUri.host.isEmpty ||
        apiUri.userInfo.isNotEmpty ||
        apiUri.hasQuery ||
        apiUri.hasFragment ||
        apiUri.host.endsWith('.invalid')) {
      issues.add('API_BASE_URL_INVALID');
    } else {
      final matchesEnvironment = switch (environment) {
        AppEnvironment.production => apiBaseUrl == productionApiBaseUrl,
        AppEnvironment.staging =>
          apiBaseUrl == apiUri.toString() && _isStagingApiUri(apiUri),
        AppEnvironment.development => true,
      };
      if (!matchesEnvironment) {
        issues.add('API_BASE_URL_ENVIRONMENT_MISMATCH');
      }
    }
    if (imageCacheMaximumSize < 1 || imageCacheMaximumSizeBytes < 1) {
      issues.add('IMAGE_CACHE_LIMIT_INVALID');
    }
    return List.unmodifiable(issues);
  }

  static bool _isStagingApiUri(Uri apiUri) {
    return apiUri.scheme == _stagingApiScheme &&
        apiUri.host == _stagingApiHost &&
        apiUri.path == _stagingApiPath &&
        apiUri.authority == _stagingApiHost &&
        !apiUri.hasPort &&
        apiUri.userInfo.isEmpty &&
        !apiUri.hasQuery &&
        !apiUri.hasFragment;
  }

  void validateForRuntime() {
    final issues = validationIssues();
    if (issues.isNotEmpty) {
      throw AppConfigurationException(issues);
    }
  }

  @override
  String toString() {
    return 'AppConfig('
        'environment: ${environment.name}, '
        'appName: $appName, '
        'loggingEnabled: $loggingEnabled'
        ')';
  }
}
