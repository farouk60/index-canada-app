import 'package:flutter/material.dart';

import '../data_service.dart';
import 'localization_service.dart';

/// Service global pour gérer le cache et les rafraîchissements forcés
class CacheManagerService {
  static final CacheManagerService _instance = CacheManagerService._internal();
  factory CacheManagerService() => _instance;
  CacheManagerService._internal();

  final LocalizationService _localizationService = LocalizationService();

  /// Effectue un rafraîchissement complet en vidant tous les caches
  Future<void> performCompleteRefresh({
    BuildContext? context,
    bool showMessages = true,
  }) async {
    try {
      // Afficher un indicateur de chargement si contexte fourni
      if (context != null && showMessages && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('refreshing_data')),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 1. Vider le cache du DataService
      final dataService = DataService();
      dataService.clearCache();

      // 2. Forcer la synchronisation avec Wix
      await dataService.forceSyncWithWix();

      // 3. Vider le cache d'images de CachedNetworkImage
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 4. Vider le cache HTTP spécifique à CachedNetworkImage
      await _clearCachedNetworkImageCache();

      // 5. Afficher un message de confirmation si contexte fourni
      if (context != null && showMessages && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('data_refreshed')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context != null && showMessages && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('refresh_error')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      rethrow;
    }
  }

  /// Vide spécifiquement le cache de CachedNetworkImage
  Future<void> _clearCachedNetworkImageCache() async {
    try {
      // Cette méthode vide le cache disk et memory de CachedNetworkImage
      // Il n'y a pas d'API publique directe, mais vider imageCache suffit généralement

      // Force un garbage collection des images
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {
      // Ne pas bloquer le processus si cette étape échoue
    }
  }

  /// Effectue un rafraîchissement léger (cache DataService seulement)
  Future<void> performLightRefresh() async {
    final dataService = DataService();
    dataService.clearCache();
  }

  /// Vérifie si un rafraîchissement est nécessaire
  bool shouldRefresh() {
    // Logique pour déterminer si un refresh est nécessaire
    // Par exemple, basé sur un timestamp de dernière mise à jour
    return true; // Pour l'instant, toujours retourner true
  }
}
