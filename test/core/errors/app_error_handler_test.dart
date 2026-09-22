import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/errors/app_error_handler.dart';
import 'package:index_canada/core/logging/app_logger.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppErrorHandler restaure les gestionnaires précédents', () {
    final initialFlutterHandler = FlutterError.onError;
    final initialPlatformHandler = PlatformDispatcher.instance.onError;
    final initialErrorWidgetBuilder = ErrorWidget.builder;

    void sentinelFlutterHandler(FlutterErrorDetails _) {}
    bool sentinelPlatformHandler(Object _, StackTrace _) => false;
    Widget sentinelErrorWidgetBuilder(FlutterErrorDetails _) {
      return const SizedBox.shrink();
    }

    try {
      FlutterError.onError = sentinelFlutterHandler;
      PlatformDispatcher.instance.onError = sentinelPlatformHandler;
      ErrorWidget.builder = sentinelErrorWidgetBuilder;

      final handler = AppErrorHandler(
        logger: AppLogger(enabled: false),
        showTechnicalDetails: false,
      );

      handler.install();
      handler.install();

      expect(FlutterError.onError, isNot(same(sentinelFlutterHandler)));
      expect(
        PlatformDispatcher.instance.onError,
        isNot(same(sentinelPlatformHandler)),
      );
      expect(ErrorWidget.builder, isNot(same(sentinelErrorWidgetBuilder)));

      handler.restore();
      handler.restore();

      expect(FlutterError.onError, same(sentinelFlutterHandler));
      expect(
        PlatformDispatcher.instance.onError,
        same(sentinelPlatformHandler),
      );
      expect(ErrorWidget.builder, same(sentinelErrorWidgetBuilder));
    } finally {
      FlutterError.onError = initialFlutterHandler;
      PlatformDispatcher.instance.onError = initialPlatformHandler;
      ErrorWidget.builder = initialErrorWidgetBuilder;
    }
  });

  testWidgets('construit un écran de repli sans détail technique', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().setLanguage('fr');
    final handler = AppErrorHandler(
      logger: AppLogger(enabled: false),
      showTechnicalDetails: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: handler.buildFallbackWidget(
          FlutterErrorDetails(exception: StateError('secret interne')),
        ),
      ),
    );

    expect(find.text('Un problème est survenu.'), findsOneWidget);
    expect(find.textContaining('Veuillez réessayer.'), findsOneWidget);
    expect(find.textContaining('secret interne'), findsNothing);
  });

  testWidgets('localise l’écran de repli global en anglais', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().setLanguage('en');
    addTearDown(() => LocalizationService().setLanguage('fr'));
    final handler = AppErrorHandler(
      logger: AppLogger(enabled: false),
      showTechnicalDetails: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: handler.buildFallbackWidget(
          FlutterErrorDetails(exception: StateError('internal secret')),
        ),
      ),
    );

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.textContaining('Please try again.'), findsOneWidget);
    expect(find.textContaining('internal secret'), findsNothing);
  });
}
