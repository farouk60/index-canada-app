import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

typedef AppLogSink = void Function(String message);

enum AppLogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warning(2, 'WARN'),
  error(3, 'ERROR');

  const AppLogLevel(this.priority, this.label);

  final int priority;
  final String label;
}

/// Journal applicatif minimal qui n'émet rien en production par défaut et
/// masque les secrets et renseignements personnels les plus courants.
final class AppLogger {
  AppLogger({
    required this.enabled,
    this.minimumLevel = AppLogLevel.info,
    AppLogSink? sink,
  }) : _sink = sink ?? _defaultSink;

  factory AppLogger.fromConfig(AppConfig config, {AppLogSink? sink}) {
    return AppLogger(
      enabled: config.loggingEnabled,
      minimumLevel: config.environment == AppEnvironment.development
          ? AppLogLevel.debug
          : AppLogLevel.info,
      sink: sink,
    );
  }

  static final RegExp _authorizationPattern = RegExp(
    r'\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(
    r'(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}',
  );
  static final RegExp _stripeKeyPattern = RegExp(
    r'\b(?:pk|sk)_(?:live|test)_[A-Za-z0-9]+\b',
  );
  static final RegExp _jwtPattern = RegExp(
    r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );
  static final RegExp _base64ImagePattern = RegExp(
    r'data:image/[^;\s]+;base64,[A-Za-z0-9+/=]+',
    caseSensitive: false,
  );
  static final RegExp _sensitiveFieldPattern = RegExp(
    r'''(["']?(?:password|passcode|token|secret|authorization|api[_-]?key|email|courriel|phone|telephone|téléphone|address|adresse)["']?\s*[:=]\s*)(["'][^"']*["']|[^,}\s]+)''',
    caseSensitive: false,
  );

  static const int _maximumMessageLength = 2000;

  final bool enabled;
  final AppLogLevel minimumLevel;
  final AppLogSink _sink;

  void debug(String message) => _write(AppLogLevel.debug, message);

  void info(String message) => _write(AppLogLevel.info, message);

  void warning(String message, {Object? error}) {
    _write(AppLogLevel.warning, message, error: error);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _write(AppLogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  void _write(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!enabled || level.priority < minimumLevel.priority) {
      return;
    }

    final buffer = StringBuffer('[${level.label}] ${sanitize(message)}');
    if (error != null) {
      buffer.write(' | ${sanitize(error.toString())}');
    }
    if (stackTrace != null && kDebugMode) {
      buffer.write('\n${sanitize(stackTrace.toString())}');
    }
    _sink(buffer.toString());
  }

  static String sanitize(String value) {
    var sanitized = value
        .replaceAll(_authorizationPattern, '[AUTORISATION_MASQUÉE]')
        .replaceAll(_stripeKeyPattern, '[CLÉ_STRIPE_MASQUÉE]')
        .replaceAll(_jwtPattern, '[JETON_MASQUÉ]')
        .replaceAll(_base64ImagePattern, '[IMAGE_MASQUÉE]')
        .replaceAll(_emailPattern, '[COURRIEL_MASQUÉ]')
        .replaceAll(_phonePattern, '[TÉLÉPHONE_MASQUÉ]')
        .replaceAllMapped(
          _sensitiveFieldPattern,
          (match) => '${match.group(1)}[VALEUR_MASQUÉE]',
        );

    if (sanitized.length > _maximumMessageLength) {
      sanitized = '${sanitized.substring(0, _maximumMessageLength)}…[TRONQUÉ]';
    }
    return sanitized;
  }

  static void _defaultSink(String message) => debugPrint(message);
}
