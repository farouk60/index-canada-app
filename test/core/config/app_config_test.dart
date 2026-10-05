import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/config/app_config.dart';

const stagingApiBaseUrl =
    'https://immigrantindex.wixsite.com/website-1/_functions';

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
      final config = buildConfig(apiBaseUrl: stagingApiBaseUrl);

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
        apiBaseUrl: stagingApiBaseUrl,
      );

      expect(config.validationIssues(), isEmpty);
    });

    test('valide tous les composants de l’URI staging', () {
      final invalidStagingUrls = <String, String>{
        'http://immigrantindex.wixsite.com/website-1/_functions':
            'API_BASE_URL_INVALID',
        'https://staging.immigrantindex.wixsite.com/website-1/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://immigrantindex.wixsite.com/website-2/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://immigrantindex.wixsite.com/website-1/_functions/':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://immigrantindex.wixsite.com:443/website-1/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://immigrantindex.wixsite.com/website-1/_functions?rc=test-site':
            'API_BASE_URL_INVALID',
        'https://immigrantindex.wixsite.com/website-1/_functions#staging':
            'API_BASE_URL_INVALID',
        'https://deploy@immigrantindex.wixsite.com/website-1/_functions':
            'API_BASE_URL_INVALID',
        'https://@immigrantindex.wixsite.com/website-1/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
      };

      for (final entry in invalidStagingUrls.entries) {
        final config = buildConfig(
          environment: AppEnvironment.staging,
          apiBaseUrl: entry.key,
        );

        expect(
          config.validationIssues(),
          contains(entry.value),
          reason: 'L’URI staging non canonique doit être refusée: ${entry.key}',
        );
      }
    });

    test('conserve le verrouillage exact du backend production', () {
      final invalidProductionUrls = <String, String>{
        'https://www.immigrantindex.com/_functions/':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://www.immigrantindex.com:443/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://immigrantindex.com/_functions':
            'API_BASE_URL_ENVIRONMENT_MISMATCH',
        'https://www.immigrantindex.com/_functions?source=release':
            'API_BASE_URL_INVALID',
        'https://www.immigrantindex.com/_functions#release':
            'API_BASE_URL_INVALID',
        'https://deploy@www.immigrantindex.com/_functions':
            'API_BASE_URL_INVALID',
      };

      for (final entry in invalidProductionUrls.entries) {
        final config = buildConfig(apiBaseUrl: entry.key);

        expect(
          config.validationIssues(),
          contains(entry.value),
          reason:
              'L’URI production non canonique doit être refusée: ${entry.key}',
        );
      }
    });
  });
}
