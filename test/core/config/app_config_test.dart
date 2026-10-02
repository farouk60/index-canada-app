import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/config/app_config.dart';

AppConfig buildConfig({
  AppEnvironment environment = AppEnvironment.production,
  String apiBaseUrl = 'https://www.immigrantindex.com/_functions',
  int imageCacheMaximumSize = 200,
  int imageCacheMaximumSizeBytes = 50 * 1024 * 1024,
}) {
  return AppConfig(
    environment: environment,
    appName: 'Index Canada',
    apiBaseUrl: apiBaseUrl,
    imageCacheMaximumSize: imageCacheMaximumSize,
    imageCacheMaximumSizeBytes: imageCacheMaximumSizeBytes,
    loggingEnabled: false,
  );
}

void main() {
  group('AppConfig.validateForRuntime', () {
    test('accepte une production mobile sans configuration Stripe', () {
      final config = buildConfig();

      expect(config.validationIssues(), isEmpty);
      expect(config.validateForRuntime, returnsNormally);
    });

    test('exige HTTPS et refuse les hôtes factices', () {
      final insecure = buildConfig(apiBaseUrl: 'http://example.com/functions');
      final placeholder = buildConfig(
        apiBaseUrl: 'https://api.example.invalid/functions',
      );

      expect(insecure.validationIssues(), contains('API_BASE_URL_INVALID'));
      expect(placeholder.validationIssues(), contains('API_BASE_URL_INVALID'));
    });

    test('refuse le backend staging dans une livraison production', () {
      final config = buildConfig(apiBaseUrl: AppConfig.stagingApiBaseUrl);

      expect(
        config.validationIssues(),
        contains('API_BASE_URL_ENVIRONMENT_MISMATCH'),
      );
      expect(
        config.validateForRuntime,
        throwsA(isA<AppConfigurationException>()),
      );
    });

    test('refuse le backend production dans une livraison staging', () {
      final config = buildConfig(
        environment: AppEnvironment.staging,
        apiBaseUrl: AppConfig.productionApiBaseUrl,
      );

      expect(
        config.validationIssues(),
        contains('API_BASE_URL_ENVIRONMENT_MISMATCH'),
      );
    });

    test('accepte uniquement l’URL canonique de staging en staging', () {
      final config = buildConfig(
        environment: AppEnvironment.staging,
        apiBaseUrl: AppConfig.stagingApiBaseUrl,
      );

      expect(config.validationIssues(), isEmpty);
    });
  });
}
