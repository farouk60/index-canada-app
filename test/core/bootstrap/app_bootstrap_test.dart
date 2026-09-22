import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/bootstrap/app_bootstrap.dart';
import 'package:index_canada/core/logging/app_logger.dart';

void main() {
  group('AppBootstrap', () {
    test('continue après l’échec d’une étape non critique', () async {
      final executionOrder = <String>[];
      final failure = StateError('service optionnel indisponible');
      final bootstrap = AppBootstrap(
        logger: AppLogger(enabled: false),
        steps: [
          BootstrapStep(
            name: 'optionnelle',
            initialize: () {
              executionOrder.add('optionnelle');
              throw failure;
            },
          ),
          BootstrapStep(
            name: 'suivante',
            initialize: () async {
              await Future<void>.delayed(Duration.zero);
              executionOrder.add('suivante');
            },
          ),
        ],
      );

      final result = await bootstrap.initialize();

      expect(executionOrder, ['optionnelle', 'suivante']);
      expect(result.succeeded, isFalse);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.stepName, 'optionnelle');
      expect(result.issues.single.error, same(failure));
    });

    test(
      'retourne un résultat réussi lorsque toutes les étapes passent',
      () async {
        final executionOrder = <String>[];
        final bootstrap = AppBootstrap(
          logger: AppLogger(enabled: false),
          steps: [
            BootstrapStep(
              name: 'synchrone',
              initialize: () => executionOrder.add('synchrone'),
            ),
            BootstrapStep(
              name: 'asynchrone',
              initialize: () async => executionOrder.add('asynchrone'),
            ),
          ],
        );

        final result = await bootstrap.initialize();

        expect(executionOrder, ['synchrone', 'asynchrone']);
        expect(result.succeeded, isTrue);
        expect(result.issues, isEmpty);
      },
    );

    test(
      'encapsule l’échec critique et interrompt les étapes suivantes',
      () async {
        final executionOrder = <String>[];
        final failure = ArgumentError('configuration obligatoire absente');
        final bootstrap = AppBootstrap(
          logger: AppLogger(enabled: false),
          steps: [
            BootstrapStep(
              name: 'critique',
              isCritical: true,
              initialize: () {
                executionOrder.add('critique');
                throw failure;
              },
            ),
            BootstrapStep(
              name: 'jamais exécutée',
              initialize: () => executionOrder.add('jamais exécutée'),
            ),
          ],
        );

        await expectLater(
          bootstrap.initialize(),
          throwsA(
            isA<BootstrapException>()
                .having(
                  (exception) => exception.stepName,
                  'stepName',
                  'critique',
                )
                .having((exception) => exception.cause, 'cause', same(failure))
                .having(
                  (exception) => exception.stackTrace,
                  'stackTrace',
                  isNotNull,
                ),
          ),
        );
        expect(executionOrder, ['critique']);
      },
    );
  });
}
