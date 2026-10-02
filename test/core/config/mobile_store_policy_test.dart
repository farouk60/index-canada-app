import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _workflowStep(String workflow, String name) {
  final marker = '- name: $name';
  final start = workflow.indexOf(marker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Étape introuvable : $name');
  final next = workflow.indexOf('\n      - name:', start + marker.length);
  return workflow.substring(start, next < 0 ? workflow.length : next);
}

void main() {
  group('politique de paiement des builds mobiles', () {
    test('le bootstrap et les manifests n’exposent plus Stripe natif', () {
      const paths = [
        'lib/core/config/app_config.dart',
        'lib/core/bootstrap/app_bootstrap.dart',
        'pubspec.yaml',
        'android/app/src/main/AndroidManifest.xml',
        'ios/Runner/Info.plist',
      ];
      final forbidden = RegExp(
        r'flutterstripe|flutter_stripe|STRIPE_(?:PUBLISHABLE_KEY|URL_SCHEME)|Stripe\.(?:instance|publishableKey|urlScheme)',
        caseSensitive: false,
      );

      for (final path in paths) {
        expect(
          _read(path),
          isNot(matches(forbidden)),
          reason: '$path réactive Stripe dans une livraison mobile',
        );
      }
    });

    test('le code Flutter livré ne référence plus PaymentSheet', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final forbidden = RegExp(
        r'flutter_stripe|stripe_native_payment_service|StripeNativePaymentService|Stripe\.instance|PaymentSheet',
      );

      for (final file in dartFiles) {
        expect(
          file.readAsStringSync(),
          isNot(matches(forbidden)),
          reason: '${file.path} expose encore le paiement Stripe natif',
        );
      }
    });

    test('les compilations mobiles CI ne reçoivent aucun secret Stripe', () {
      final ci = _read('.github/workflows/ci.yml');
      final androidRelease = _read('.github/workflows/android-release.yml');
      final release = _read('.github/workflows/ios-release.yml');
      final mobileSteps = [
        _workflowStep(ci, 'Compiler le bundle Android release sans signature'),
        _workflowStep(ci, 'Compiler la cible iOS sans signature'),
        _workflowStep(androidRelease, "Compiler l'AAB de production signé"),
        _workflowStep(release, "Compiler l'IPA App Store"),
      ];

      for (final step in mobileSteps) {
        expect(step, isNot(contains('STRIPE_')));
      }
      expect(ci, isNot(contains('STRIPE_PUBLISHABLE_KEY')));
      expect(androidRelease, isNot(contains('IOS_STRIPE_PUBLISHABLE_KEY')));
      expect(release, isNot(contains('IOS_STRIPE_PUBLISHABLE_KEY')));
    });

    test('la release Android verrouille le build et le backend production', () {
      final release = _read('.github/workflows/android-release.yml');

      expect(release, contains('refs/heads/main'));
      expect(release, contains('MOBILE_PRODUCTION_APPROVED_SHA'));
      expect(release, contains('1.1.0+28'));
      expect(
        release,
        contains('API_BASE_URL=https://www.immigrantindex.com/_functions'),
      );
      expect(
        release,
        contains('https://immigrantindex.wixsite.com/website-1/_functions'),
      );
      expect(release, contains('GOOGLE_PLAY_UPLOAD_SERVICE_ACCOUNT_JSON'));
      expect(release, isNot(contains('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON:')));
    });

    test('la release iOS prouve l’URL production compilée', () {
      final release = _read('.github/workflows/ios-release.yml');

      expect(release, contains('MOBILE_PRODUCTION_APPROVED_SHA'));
      expect(release, contains('1.1.0+28'));
      expect(release, contains(r'grep -Fq "$PRODUCTION_API_BASE_URL"'));
      expect(release, contains(r'$FORBIDDEN_STAGING_API_BASE_URL'));
      expect(release, contains(r'$FORBIDDEN_CI_API_BASE_URL'));
    });

    test('la release iOS est testée et lit sa version depuis pubspec', () {
      final release = _read('.github/workflows/ios-release.yml');

      expect(
        release,
        contains(
          'needs:\n'
          '      - release-quality\n'
          '      - backend-store-billing-quality',
        ),
      );
      expect(
        release,
        contains('flutter analyze --fatal-infos --fatal-warnings'),
      );
      expect(release, contains('flutter test --reporter expanded'));
      expect(release, contains('npm test --prefix backend'));
      expect(
        release,
        contains('npm audit --prefix backend --omit=dev --audit-level=high'),
      );
      expect(release, contains(r'''version_value="$(awk '$1 == "version:"'''));
      expect(release, contains('steps.app_version.outputs.version_name'));
      expect(release, contains('steps.app_version.outputs.build_number'));
      expect(release, isNot(contains('index-canada-ios-1.1.0-25-encrypted')));
    });
  });
}
