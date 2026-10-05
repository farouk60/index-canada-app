import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _workflowStep(String workflow, String name) {
  final marker = '- name: $name';
  final start = workflow.indexOf(marker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Étape introuvable : $name');
  final next = workflow.indexOf('\n      - name:', start + marker.length);
  return workflow.substring(start, next < 0 ? workflow.length : next);
}

String _workflowJob(String workflow, String id) {
  final marker = '  $id:\n';
  final start = workflow.indexOf(marker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Job introuvable : $id');
  final nextJob = RegExp(
    r'^  [A-Za-z0-9][A-Za-z0-9_-]*:[ \t]*\r?$',
    multiLine: true,
  ).allMatches(workflow, start + marker.length);
  final end = nextJob.isEmpty ? workflow.length : nextJob.first.start;
  return workflow.substring(start, end);
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

    test('le code Flutter livré n’embarque aucune URL non-production', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      const forbiddenUrls = [
        'https://immigrantindex.wixsite.com/website-1/_functions',
        'https://ci.index-canada.example/_functions',
      ];

      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        for (final forbiddenUrl in forbiddenUrls) {
          expect(
            source,
            isNot(contains(forbiddenUrl)),
            reason: '${file.path} embarque encore une URL non-production',
          );
        }
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
      final signedJob = _workflowJob(release, 'signed-aab');
      final uploadJob = _workflowJob(release, 'upload-google-play');
      final oidcStep = _workflowStep(
        uploadJob,
        'Obtenir un jeton éphémère Google Play',
      );
      final uploadStep = _workflowStep(
        uploadJob,
        'Téléverser vers le test interne Google Play',
      );
      final encryptedArtifactStep = _workflowStep(
        signedJob,
        "Publier uniquement l'AAB production chiffré",
      );
      final downloadArtifactStep = _workflowStep(
        uploadJob,
        "Télécharger uniquement l'AAB production chiffré",
      );
      final verifyDownloadedBundleStep = _workflowStep(
        uploadJob,
        "Déchiffrer et revérifier l'AAB avant envoi",
      );

      expect(release, contains('refs/heads/main'));
      expect(release, contains('MOBILE_PRODUCTION_APPROVED_SHA'));
      expect(release, contains('1.1.0+28'));
      expect(release, isNot(contains('apkanalyzer')));
      for (final job in [signedJob, uploadJob]) {
        final install = _workflowStep(job, 'Installer bundletool vérifié');
        expect(install, contains('bundletool-all-1.18.3.jar'));
        expect(
          install,
          contains(
            'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29',
          ),
        );
        expect(install, contains('sha256sum --check --strict'));
        expect(install, contains('set -euo pipefail'));
        expect(job, contains("--xpath='/manifest/@package'"));
        expect(job, contains("--xpath='/manifest/@android:versionCode'"));
        expect(
          job.indexOf('Installer bundletool vérifié'),
          lessThan(job.indexOf('dump manifest')),
        );
      }
      expect(
        release,
        contains('API_BASE_URL=https://www.immigrantindex.com/_functions'),
      );
      expect(
        release,
        contains('https://immigrantindex.wixsite.com/website-1/_functions'),
      );
      expect(
        uploadJob,
        contains(
          'permissions:\n'
          '      contents: read\n'
          '      id-token: write',
        ),
      );
      expect(
        RegExp(
          r'^[ \t]*id-token:[ \t]*write[ \t]*\r?$',
          multiLine: true,
        ).allMatches(release).length,
        1,
      );
      expect(signedJob, isNot(contains('id-token: write')));
      expect(signedJob, isNot(contains('google-github-actions/auth@')));
      expect(
        uploadJob,
        contains(
          'needs:\n'
          '      - release-gate\n'
          '      - quality\n'
          '      - signed-aab',
        ),
      );
      expect(uploadJob, contains(r'if: ${{ inputs.upload_internal }}'));
      expect(uploadJob, contains('environment: mobile-staging'));
      expect(
        oidcStep,
        contains(
          'google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093',
        ),
      );
      expect(
        oidcStep,
        contains(
          'projects/762725959551/locations/global/workloadIdentityPools/'
          'github-index-canada/providers/index-canada-android-release',
        ),
      );
      expect(
        oidcStep,
        contains(
          'indexca-play-uploader-prod@index-immigrant-index-2025.iam.gserviceaccount.com',
        ),
      );
      expect(oidcStep, contains('token_format: access_token'));
      expect(
        oidcStep,
        contains(
          'access_token_scopes: https://www.googleapis.com/auth/androidpublisher',
        ),
      );
      expect(oidcStep, contains('access_token_lifetime: 900s'));
      expect(oidcStep, contains('create_credentials_file: false'));
      expect(
        downloadArtifactStep,
        contains(
          'actions/download-artifact@634f93cb2916e3fdff6788551b99b062d0335ce0',
        ),
      );
      expect(
        downloadArtifactStep,
        contains(r'name: ${{ needs.signed-aab.outputs.artifact_name }}'),
      );
      expect(
        encryptedArtifactStep,
        contains(r'path: ${{ steps.encrypted_bundle.outputs.encrypted_path }}'),
      );
      expect(encryptedArtifactStep, contains('retention-days: 1'));
      expect(
        encryptedArtifactStep,
        isNot(contains(r'path: ${{ steps.bundle.outputs.bundle_path }}')),
      );
      expect(
        verifyDownloadedBundleStep,
        contains('openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000'),
      );
      expect(verifyDownloadedBundleStep, contains(r'sha256sum "$AAB_PATH"'));
      expect(
        verifyDownloadedBundleStep,
        contains(r'jarsigner -verify "$AAB_PATH"'),
      );
      expect(
        verifyDownloadedBundleStep,
        contains(
          r'''dump manifest --bundle="$AAB_PATH" --xpath='/manifest/@package' '''
              .trim(),
        ),
      );
      expect(
        verifyDownloadedBundleStep,
        contains(
          r'''dump manifest --bundle="$AAB_PATH" --xpath='/manifest/@android:versionCode' '''
              .trim(),
        ),
      );
      expect(
        verifyDownloadedBundleStep,
        contains(r'grep -Fq "$API_BASE_URL" "$app_strings"'),
      );
      expect(
        verifyDownloadedBundleStep,
        contains(r'$FORBIDDEN_STAGING_API_BASE_URL'),
      );
      expect(
        verifyDownloadedBundleStep,
        contains(r'$FORBIDDEN_CI_API_BASE_URL'),
      );
      expect(
        uploadStep,
        contains(r'AAB_PATH: ${{ steps.verified_bundle.outputs.aab_path }}'),
      );
      expect(
        uploadStep,
        contains(
          r'GOOGLE_PLAY_ACCESS_TOKEN: ${{ steps.google_play_auth.outputs.access_token }}',
        ),
      );
      expect(uploadStep, contains('new OAuth2Client()'));
      expect(uploadJob, contains('npm ci --prefix backend --ignore-scripts'));
      expect(
        uploadStep,
        contains('auth.setCredentials({ access_token: accessToken })'),
      );
      expect(uploadStep, isNot(contains('GoogleAuth')));
      expect(
        release.indexOf('- name: Obtenir un jeton éphémère Google Play'),
        lessThan(
          release.indexOf(
            '- name: Téléverser vers le test interne Google Play',
          ),
        ),
      );
      expect(
        release,
        isNot(contains('GOOGLE_PLAY_UPLOAD_SERVICE_ACCOUNT_JSON')),
      );
      expect(release, isNot(contains('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON:')));
      expect(
        signedJob,
        contains(
          'AAB 1.1.0 (28) vérifié et archivé; aucun téléversement Google Play demandé.',
        ),
      );
      expect(
        uploadJob,
        contains(
          'AAB 1.1.0 (28) vérifié et téléversé vers le test interne Google Play.',
        ),
      );
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
