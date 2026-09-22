import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../services/firebase_analytics_service.dart';
import '../../services/ios_optimization_service.dart';
import '../../services/localization_service.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';

typedef BootstrapAction = FutureOr<void> Function();

final class BootstrapStep {
  const BootstrapStep({
    required this.name,
    required this.initialize,
    this.isCritical = false,
  });

  final String name;
  final BootstrapAction initialize;
  final bool isCritical;
}

final class BootstrapIssue {
  const BootstrapIssue({
    required this.stepName,
    required this.error,
    required this.stackTrace,
  });

  final String stepName;
  final Object error;
  final StackTrace stackTrace;
}

final class BootstrapResult {
  BootstrapResult({required List<BootstrapIssue> issues})
    : issues = List.unmodifiable(issues);

  final List<BootstrapIssue> issues;

  bool get succeeded => issues.isEmpty;
}

final class BootstrapException implements Exception {
  const BootstrapException({
    required this.stepName,
    required this.cause,
    required this.stackTrace,
  });

  final String stepName;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'BootstrapException(step: $stepName)';
}

/// Orchestre les initialisations de manière déterministe et testable.
///
/// Les tests peuvent fournir leur propre liste de [BootstrapStep] sans charger
/// de plugiciel natif. En production, un échec non critique est consigné puis
/// l'application continue avec les valeurs de repli existantes.
final class AppBootstrap {
  AppBootstrap({required Iterable<BootstrapStep> steps, required this.logger})
    : _steps = List.unmodifiable(steps);

  factory AppBootstrap.production({
    required AppConfig config,
    required AppLogger logger,
  }) {
    return AppBootstrap(
      logger: logger,
      steps: [
        const BootstrapStep(
          name: 'optimisations de la plateforme',
          initialize: IOSOptimizationService.configureIOSOptimizations,
        ),
        BootstrapStep(
          name: 'analytique respectueuse de la vie privée',
          initialize: FirebaseAnalyticsService().initialize,
        ),
        BootstrapStep(
          name: 'préférences linguistiques',
          initialize: LocalizationService().loadSavedLanguage,
        ),
        BootstrapStep(
          name: 'paiement Stripe',
          initialize: () => _configureStripe(config, logger),
        ),
        BootstrapStep(
          name: 'cache d\'images',
          initialize: () => _configureImageCache(config),
        ),
      ],
    );
  }

  final List<BootstrapStep> _steps;
  final AppLogger logger;

  Future<BootstrapResult> initialize() async {
    final issues = <BootstrapIssue>[];

    for (final step in _steps) {
      try {
        await Future<void>.sync(step.initialize);
        logger.debug('Initialisation terminée : ${step.name}');
      } catch (error, stackTrace) {
        logger.error(
          'Initialisation impossible : ${step.name}',
          error: error,
          stackTrace: stackTrace,
        );
        issues.add(
          BootstrapIssue(
            stepName: step.name,
            error: error,
            stackTrace: stackTrace,
          ),
        );

        if (step.isCritical) {
          throw BootstrapException(
            stepName: step.name,
            cause: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return BootstrapResult(issues: issues);
  }

  static Future<void> _configureStripe(
    AppConfig config,
    AppLogger logger,
  ) async {
    if (kIsWeb) {
      logger.info(
        'PaymentSheet Stripe est désactivé sur Web; le forfait gratuit reste disponible.',
      );
      return;
    }

    if (!config.hasValidStripeConfiguration) {
      logger.warning(
        'Configuration Stripe absente ou invalide; le paiement sera indisponible.',
      );
      return;
    }

    Stripe.publishableKey = config.stripePublishableKey.trim();
    Stripe.urlScheme = config.stripeUrlScheme.trim();
    await Stripe.instance.applySettings();
  }

  static void _configureImageCache(AppConfig config) {
    CachedNetworkImage.logLevel = CacheManagerLogLevel.none;
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = config.imageCacheMaximumSize;
    imageCache.maximumSizeBytes = config.imageCacheMaximumSizeBytes;
  }
}
