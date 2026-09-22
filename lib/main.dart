import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/config/app_config.dart';
import 'core/errors/app_error_handler.dart';
import 'core/logging/app_logger.dart';
import 'services/localization_service.dart';
import 'theme/app_theme.dart';
import 'widgets/main_navigation.dart';

Future<void> main() async {
  final config = AppConfig.current;
  final logger = AppLogger.fromConfig(config);
  final errorHandler = AppErrorHandler(logger: logger);
  final execution = runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      errorHandler.install();

      config.validateForRuntime(supportsNativePayments: !kIsWeb);

      final bootstrap = AppBootstrap.production(config: config, logger: logger);
      await bootstrap.initialize();

      runApp(MyApp(config: config));
    },
    errorHandler.handleZoneError,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (logger.enabled) {
          parent.print(zone, AppLogger.sanitize(line));
        }
      },
    ),
  );

  if (execution != null) {
    await execution;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.config});

  final AppConfig? config;

  @override
  Widget build(BuildContext context) {
    final appConfig = config ?? AppConfig.current;
    final localization = LocalizationService();

    return ListenableBuilder(
      listenable: localization,
      builder: (context, _) => MaterialApp(
        title: appConfig.appName,
        locale: Locale(localization.currentLanguage, 'CA'),
        supportedLocales: const [Locale('fr', 'CA'), Locale('en', 'CA')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // Le thème sombre sera activé après migration des écrans historiques
        // qui utilisent encore des couleurs claires codées en dur.
        themeMode: ThemeMode.light,
        home: const MainNavigationPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
