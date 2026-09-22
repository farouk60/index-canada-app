import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/localization_service.dart';
import '../logging/app_logger.dart';

/// Installe un point de capture commun pour les erreurs Flutter et asynchrones.
///
/// [restore] permet aux tests de remettre les gestionnaires précédents.
final class AppErrorHandler {
  AppErrorHandler({
    required this.logger,
    this.showTechnicalDetails = kDebugMode,
  });

  final AppLogger logger;
  final bool showTechnicalDetails;

  FlutterExceptionHandler? _previousFlutterErrorHandler;
  ErrorCallback? _previousPlatformErrorHandler;
  ErrorWidgetBuilder? _previousErrorWidgetBuilder;
  bool _isInstalled = false;

  void install() {
    if (_isInstalled) {
      return;
    }

    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    _previousErrorWidgetBuilder = ErrorWidget.builder;

    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformError;
    if (!showTechnicalDetails) {
      ErrorWidget.builder = buildFallbackWidget;
    }
    _isInstalled = true;
  }

  void restore() {
    if (!_isInstalled) {
      return;
    }

    FlutterError.onError = _previousFlutterErrorHandler;
    PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    final previousBuilder = _previousErrorWidgetBuilder;
    if (previousBuilder != null) {
      ErrorWidget.builder = previousBuilder;
    }
    _isInstalled = false;
  }

  void handleFlutterError(FlutterErrorDetails details) {
    logger.error(
      'Erreur Flutter non gérée',
      error: details.exception,
      stackTrace: details.stack,
    );

    if (showTechnicalDetails) {
      FlutterError.presentError(details);
    }
  }

  bool handlePlatformError(Object error, StackTrace stackTrace) {
    logger.error(
      'Erreur asynchrone non gérée',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  }

  void handleZoneError(Object error, StackTrace stackTrace) {
    logger.error(
      'Erreur de zone non gérée',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Widget buildFallbackWidget(FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                SizedBox(height: 16),
                _LocalizedFallbackTitle(),
                SizedBox(height: 8),
                _LocalizedFallbackBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalizedFallbackTitle extends StatelessWidget {
  const _LocalizedFallbackTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocalizationService().tr('unexpected_error_title'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }
}

class _LocalizedFallbackBody extends StatelessWidget {
  const _LocalizedFallbackBody();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocalizationService().tr('unexpected_error_body'),
      textAlign: TextAlign.center,
    );
  }
}
