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
///
/// La clé Stripe n'a volontairement aucune valeur par défaut : les builds qui
/// activent le paiement doivent fournir `STRIPE_PUBLISHABLE_KEY`.
@immutable
final class AppConfig {
  static const requiredStripeUrlScheme = 'flutterstripe';

  const AppConfig({
    required this.environment,
    required this.appName,
    required this.apiBaseUrl,
    required this.stripePublishableKey,
    required this.stripeUrlScheme,
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
        defaultValue: 'https://www.immigrantindex.com/_functions',
      ),
      stripePublishableKey: const String.fromEnvironment(
        'STRIPE_PUBLISHABLE_KEY',
        defaultValue: '',
      ),
      stripeUrlScheme: const String.fromEnvironment(
        'STRIPE_URL_SCHEME',
        defaultValue: requiredStripeUrlScheme,
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
  final String stripePublishableKey;
  final String stripeUrlScheme;
  final int imageCacheMaximumSize;
  final int imageCacheMaximumSizeBytes;
  final bool loggingEnabled;

  bool get hasValidStripeConfiguration {
    final key = stripePublishableKey.trim();
    return RegExp(r'^pk_(?:test|live)_[A-Za-z0-9]{16,}$').hasMatch(key) &&
        stripeUrlScheme.trim() == requiredStripeUrlScheme;
  }

  /// Vérifie les invariants qui doivent être vrais dans toute livraison.
  ///
  /// Les environnements de développement et de préproduction peuvent
  /// volontairement désactiver Stripe. En production native, une clé
  /// publiable *live* est obligatoire; le Web n'utilise pas PaymentSheet.
  List<String> validationIssues({required bool supportsNativePayments}) {
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
    }
    if (imageCacheMaximumSize < 1 || imageCacheMaximumSizeBytes < 1) {
      issues.add('IMAGE_CACHE_LIMIT_INVALID');
    }
    // AndroidManifest.xml et Info.plist déclarent ce schéma. Accepter une
    // autre valeur ici casserait silencieusement le retour PaymentSheet.
    if (stripeUrlScheme.trim() != requiredStripeUrlScheme) {
      issues.add('STRIPE_URL_SCHEME_INVALID');
    }
    if (supportsNativePayments &&
        stripePublishableKey.trim().isNotEmpty &&
        !hasValidStripeConfiguration) {
      issues.add('STRIPE_PUBLISHABLE_KEY_INVALID');
    }
    if (environment == AppEnvironment.production &&
        supportsNativePayments &&
        !RegExp(r'^pk_live_[A-Za-z0-9]{16,}$')
            .hasMatch(stripePublishableKey.trim())) {
      issues.add('STRIPE_LIVE_KEY_REQUIRED');
    }

    return List.unmodifiable(issues);
  }

  void validateForRuntime({required bool supportsNativePayments}) {
    final issues = validationIssues(
      supportsNativePayments: supportsNativePayments,
    );
    if (issues.isNotEmpty) {
      throw AppConfigurationException(issues);
    }
  }

  @override
  String toString() {
    return 'AppConfig('
        'environment: ${environment.name}, '
        'appName: $appName, '
        'stripeConfigured: $hasValidStripeConfiguration, '
        'loggingEnabled: $loggingEnabled'
        ')';
  }
}
