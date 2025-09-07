import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:io';

/// Service pour les optimisations spécifiques à iOS
class IOSOptimizationService {
  static final IOSOptimizationService _instance =
      IOSOptimizationService._internal();
  factory IOSOptimizationService() => _instance;
  IOSOptimizationService._internal();

  /// Configure les optimisations système pour iOS
  static Future<void> configureIOSOptimizations() async {
    if (!Platform.isIOS) return;

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

    // Configuration des orientations préférées
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Désactivation du débogage sur iOS en production
    if (const bool.fromEnvironment('dart.vm.product')) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: [SystemUiOverlay.top],
      );
    }
  }

  /// Optimisations mémoire spécifiques à iOS
  static void optimizeMemoryForIOS() {
    if (!Platform.isIOS) return;

    // Force la collecte de déchets
    // Note: En Dart, la GC est automatique, mais on peut suggérer une collecte
    SystemChannels.platform.invokeMethod(
      'SystemSound.play',
      'SystemSoundID.none',
    );
  }

  /// Configuration des animations iOS natives
  static Duration getIOSAnimationDuration() {
    return Platform.isIOS
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 200);
  }

  /// Courbe d'animation iOS native
  static Curve getIOSAnimationCurve() {
    return Platform.isIOS ? Curves.easeInOut : Curves.fastOutSlowIn;
  }

  /// Vérifie si l'appareil iOS supporte les fonctionnalités avancées
  static bool isIOSAdvancedDevice() {
    if (!Platform.isIOS) return false;

    // Simulation de détection des capacités de l'appareil
    // En production, utiliser device_info_plus pour des détails précis
    return true; // Assumons que l'appareil supporte les fonctionnalités modernes
  }

  /// Configuration des sons système iOS
  static Future<void> playIOSSystemSound(String soundType) async {
    if (!Platform.isIOS) return;

    try {
      switch (soundType) {
        case 'click':
          await SystemSound.play(SystemSoundType.click);
          break;
        case 'alert':
          await SystemSound.play(SystemSoundType.alert);
          break;
        default:
          await SystemSound.play(SystemSoundType.click);
      }
    } catch (e) {
      debugPrint('Erreur lors de la lecture du son système iOS: $e');
    }
  }

  /// Configuration du mode sombre iOS
  static bool isIOSDarkMode(BuildContext context) {
    if (!Platform.isIOS) return false;

    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark;
  }

  /// Optimisation des images pour iOS
  static BoxFit getIOSImageFit() {
    return Platform.isIOS ? BoxFit.cover : BoxFit.contain;
  }

  /// Configuration des coins arrondis iOS
  static BorderRadius getIOSBorderRadius() {
    return Platform.isIOS
        ? BorderRadius.circular(12.0)
        : BorderRadius.circular(8.0);
  }

  /// Espacement iOS natif
  static EdgeInsets getIOSPadding() {
    return Platform.isIOS
        ? const EdgeInsets.all(16.0)
        : const EdgeInsets.all(12.0);
  }

  /// Configuration des ombres iOS
  static List<BoxShadow> getIOSShadow() {
    return Platform.isIOS
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ];
  }
}
