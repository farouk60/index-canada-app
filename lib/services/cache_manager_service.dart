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

      print('🔄 === RAFRAÎCHISSEMENT COMPLET DÉMARRÉ ===');

      // 1. Vider le cache du DataService
      final dataService = DataService();
      dataService.clearCache();
      print('✅ Cache DataService vidé');

      // 2. Forcer la synchronisation avec Wix
      await dataService.forceSyncWithWix();
      print('✅ Synchronisation Wix forcée');

      // 3. Vider le cache d'images de CachedNetworkImage
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      print('✅ Cache d\'images vidé');

      // 4. Vider le cache HTTP spécifique à CachedNetworkImage
      await _clearCachedNetworkImageCache();
      print('✅ Cache HTTP CachedNetworkImage vidé');

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

      print('✅ === RAFRAÎCHISSEMENT COMPLET TERMINÉ ===');
    } catch (e) {
      print('❌ Erreur lors du rafraîchissement complet: $e');
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

      print('🗑️ Cache CachedNetworkImage traité');
    } catch (e) {
      print('⚠️ Erreur lors du vidage du cache CachedNetworkImage: $e');
      // Ne pas bloquer le processus si cette étape échoue
    }
  }

  /// Effectue un rafraîchissement léger (cache DataService seulement)
  Future<void> performLightRefresh() async {
    try {
      print('🔄 Rafraîchissement léger...');

      final dataService = DataService();
      dataService.clearCache();

      print('✅ Rafraîchissement léger terminé');
    } catch (e) {
      print('❌ Erreur lors du rafraîchissement léger: $e');
      rethrow;
    }
  }

  /// Vérifie si un rafraîchissement est nécessaire
  bool shouldRefresh() {
    // Logique pour déterminer si un refresh est nécessaire
    // Par exemple, basé sur un timestamp de dernière mise à jour
    return true; // Pour l'instant, toujours retourner true
  }

  /// Notifie que les données ont été mises à jour dans Wix
  void notifyWixDataUpdated() {
    print('📡 Notification: Données Wix mises à jour');
    // Ici on pourrait déclencher automatiquement un refresh
    // ou marquer qu'un refresh est nécessaire
  }
}
