import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/config/app_config.dart';

AppConfig buildConfig({
  AppEnvironment environment = AppEnvironment.production,
  String apiBaseUrl = 'https://www.immigrantindex.com/_functions',
  String stripePublishableKey = 'pk_live_1234567890ABCDEF',
  String stripeUrlScheme = AppConfig.requiredStripeUrlScheme,
  int imageCacheMaximumSize = 200,
  int imageCacheMaximumSizeBytes = 50 * 1024 * 1024,
}) {
  return AppConfig(
    environment: environment,
    appName: 'Index Canada',
    apiBaseUrl: apiBaseUrl,
    stripePublishableKey: stripePublishableKey,
    stripeUrlScheme: stripeUrlScheme,
    imageCacheMaximumSize: imageCacheMaximumSize,
    imageCacheMaximumSizeBytes: imageCacheMaximumSizeBytes,
    loggingEnabled: false,
  );
}

void main() {
  group('AppConfig.validateForRuntime', () {
    test('accepte une configuration de production native complète', () {
      final config = buildConfig();

      expect(config.validationIssues(supportsNativePayments: true), isEmpty);
      expect(
        () => config.validateForRuntime(supportsNativePayments: true),
        returnsNormally,
      );
    });

    test('exige HTTPS et refuse les hôtes factices', () {
      final insecure = buildConfig(apiBaseUrl: 'http://example.com/functions');
      final placeholder = buildConfig(
        apiBaseUrl: 'https://api.example.invalid/functions',
      );

      expect(
        insecure.validationIssues(supportsNativePayments: false),
        contains('API_BASE_URL_INVALID'),
      );
      expect(
        placeholder.validationIssues(supportsNativePayments: false),
        contains('API_BASE_URL_INVALID'),
      );
    });

    test('exige une clé Stripe live en production native', () {
      final missing = buildConfig(stripePublishableKey: '');
      final testKey = buildConfig(
        stripePublishableKey: 'pk_test_1234567890ABCDEF',
      );

      expect(
        missing.validationIssues(supportsNativePayments: true),
        contains('STRIPE_LIVE_KEY_REQUIRED'),
      );
      expect(
        testKey.validationIssues(supportsNativePayments: true),
        contains('STRIPE_LIVE_KEY_REQUIRED'),
      );
      expect(
        () => testKey.validateForRuntime(supportsNativePayments: true),
        throwsA(isA<AppConfigurationException>()),
      );
    });

    test('n’exige pas de clé native sur Web', () {
      final config = buildConfig(stripePublishableKey: '');

      expect(config.validationIssues(supportsNativePayments: false), isEmpty);
    });

    test('autorise une clé de test en préproduction native', () {
      final config = buildConfig(
        environment: AppEnvironment.staging,
        stripePublishableKey: 'pk_test_1234567890ABCDEF',
      );

      expect(config.validationIssues(supportsNativePayments: true), isEmpty);
    });

    test('refuse une clé Stripe native mal formée', () {
      final config = buildConfig(
        environment: AppEnvironment.staging,
        stripePublishableKey: 'pk_test_placeholder',
      );

      expect(
        config.validationIssues(supportsNativePayments: true),
        contains('STRIPE_PUBLISHABLE_KEY_INVALID'),
      );
    });

    test('refuse un schéma Stripe différent des manifestes natifs', () {
      final config = buildConfig(stripeUrlScheme: 'indexcanada');

      expect(
        config.validationIssues(supportsNativePayments: true),
        contains('STRIPE_URL_SCHEME_INVALID'),
      );
    });
  });
}
