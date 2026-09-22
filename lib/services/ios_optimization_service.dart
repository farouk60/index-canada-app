import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service pour les optimisations spécifiques à iOS
class IOSOptimizationService {
  static final IOSOptimizationService _instance =
      IOSOptimizationService._internal();
  factory IOSOptimizationService() => _instance;
  IOSOptimizationService._internal();

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Configure les optimisations système pour iOS
  static Future<void> configureIOSOptimizations() async {
    if (!_isIOS) return;

    // Configuration de la barre de statut iOS
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Désactivation du débogage sur iOS en production
    if (const bool.fromEnvironment('dart.vm.product')) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: [SystemUiOverlay.top],
      );
    }
  }

  /// Configuration des animations iOS natives
  static Duration getIOSAnimationDuration() {
    return _isIOS
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 200);
  }

  /// Courbe d'animation iOS native
  static Curve getIOSAnimationCurve() {
    return _isIOS ? Curves.easeInOut : Curves.fastOutSlowIn;
  }

  /// Configuration du mode sombre iOS
  static bool isIOSDarkMode(BuildContext context) {
    if (!_isIOS) return false;

    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark;
  }

  /// Configuration des coins arrondis iOS
  static BorderRadius getIOSBorderRadius() {
    return _isIOS ? BorderRadius.circular(12.0) : BorderRadius.circular(8.0);
  }

  /// Espacement iOS natif
  static EdgeInsets getIOSPadding() {
    return _isIOS ? const EdgeInsets.all(16.0) : const EdgeInsets.all(12.0);
  }

  /// Configuration des ombres iOS
  static List<BoxShadow> getIOSShadow() {
    return _isIOS
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ];
  }
}
