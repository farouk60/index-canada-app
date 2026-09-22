import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/logging/app_logger.dart';

void main() {
  group('AppLogger', () {
    final sensitiveCases = [
      (
        label: 'un courriel',
        value: 'farouk.rahem@example.ca',
        replacement: '[COURRIEL_MASQUÉ]',
      ),
      (
        label: 'un téléphone canadien',
        value: '+1 (514) 555-0101',
        replacement: '[TÉLÉPHONE_MASQUÉ]',
      ),
      (
        label: 'un jeton Bearer',
        value: 'Bearer abc.DEF-123_xyz',
        replacement: '[AUTORISATION_MASQUÉE]',
      ),
      (
        label: 'une clé Stripe secrète',
        value: ['sk', 'live', '51ABCdef0123456789'].join('_'),
        replacement: '[CLÉ_STRIPE_MASQUÉE]',
      ),
      (
        label: 'une clé Stripe publiable',
        value: ['pk', 'test', '51ABCdef0123456789'].join('_'),
        replacement: '[CLÉ_STRIPE_MASQUÉE]',
      ),
      (
        label: 'une image Base64',
        value: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==',
        replacement: '[IMAGE_MASQUÉE]',
      ),
    ];

    for (final sensitiveCase in sensitiveCases) {
      test('masque ${sensitiveCase.label}', () {
        final output = <String>[];
        final logger = AppLogger(
          enabled: true,
          minimumLevel: AppLogLevel.debug,
          sink: output.add,
        );

        logger.info('Donnée reçue : ${sensitiveCase.value}');

        expect(output, hasLength(1));
        expect(output.single, contains(sensitiveCase.replacement));
        expect(output.single, isNot(contains(sensitiveCase.value)));
      });
    }

    test('masque aussi les données sensibles contenues dans une erreur', () {
      final output = <String>[];
      final logger = AppLogger(enabled: true, sink: output.add);

      logger.error(
        'Échec de la requête',
        error: StateError('Bearer secret-token-123'),
      );

      expect(output.single, contains('[AUTORISATION_MASQUÉE]'));
      expect(output.single, isNot(contains('secret-token-123')));
    });

    test('ne produit aucune sortie lorsqu’il est désactivé', () {
      final output = <String>[];
      final logger = AppLogger(enabled: false, sink: output.add);

      logger.error('Cette valeur ne doit pas sortir');

      expect(output, isEmpty);
    });

    test('respecte le niveau minimal configuré', () {
      final output = <String>[];
      final logger = AppLogger(
        enabled: true,
        minimumLevel: AppLogLevel.warning,
        sink: output.add,
      );

      logger.debug('Diagnostic');
      logger.info('Information');
      logger.warning('Avertissement');

      expect(output, hasLength(1));
      expect(output.single, startsWith('[WARN]'));
    });
  });
}
