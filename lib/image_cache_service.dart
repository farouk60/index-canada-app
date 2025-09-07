import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:convert';
import 'utils.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  // Getter pour accéder à l'instance singleton
  static ImageCacheService get instance => _instance;

  // Cache manager personnalisé pour les images
  static final CacheManager _cacheManager = CacheManager(
    Config(
      'professional_images',
      stalePeriod: const Duration(days: 7), // Cache pendant 7 jours
      maxNrOfCacheObjects: 500, // Augmenté pour plus d'images
      repo: JsonCacheInfoRepository(databaseName: 'professional_images'),
    ),
  );

  // Cache manager spécialisé pour les services (images plus petites)
  static final CacheManager _servicesCacheManager = CacheManager(
    Config(
      'services_images',
      stalePeriod: const Duration(
        days: 30, // Cache très long pour les services (30 jours)
      ),
      maxNrOfCacheObjects: 1000, // Beaucoup plus d'images de services en cache
      repo: JsonCacheInfoRepository(databaseName: 'services_images'),
    ),
  );
  // Précharger une image
  Future<void> preloadImage(String imageUrl, BuildContext context) async {
    if (!context.mounted) return;

    try {
      final validUrl = getValidImageUrl(imageUrl);

      // Précharger avec le cache manager
      await _cacheManager.getSingleFile(validUrl);

      // Vérifier si le context est toujours valide
      if (!context.mounted) return;

      // Précharger aussi pour Flutter
      await precacheImage(
        CachedNetworkImageProvider(validUrl, cacheManager: _cacheManager),
        context,
      );
    } catch (e) {
      // Ignorer les erreurs de préchargement
    }
  }

  // Précharger plusieurs images
  Future<void> preloadImages(
    List<String> imageUrls,
    BuildContext context,
  ) async {
    final futures = imageUrls.map((url) => preloadImage(url, context));
    await Future.wait(futures);
  }

  // --- MÉTHODES SPÉCIALISÉES POUR LES SERVICES ---

  // Précharger une image de service avec le cache dédié
  Future<void> preloadServiceImage(
    String imageUrl,
    BuildContext context,
  ) async {
    if (!context.mounted) return;

    try {
      final validUrl = getValidImageUrl(imageUrl);

      // Précharger avec le cache manager des services
      await _servicesCacheManager.getSingleFile(validUrl);

      // Vérifier si le context est toujours valide
      if (!context.mounted) return;

      // Précharger aussi pour Flutter avec le bon cache manager
      await precacheImage(
        CachedNetworkImageProvider(
          validUrl,
          cacheManager: _servicesCacheManager,
        ),
        context,
      );
    } catch (e) {
      // Erreur silencieuse pour ne pas ralentir l'interface
    }
  }

  // Précharger toutes les images de services avec limitation de concurrence
  Future<void> preloadAllServiceImages(
    List<String> serviceImageUrls,
    BuildContext context,
  ) async {
    if (serviceImageUrls.isEmpty || !context.mounted) return;

    // Précharger par petits groupes pour éviter la surcharge
    const batchSize = 3;
    for (int i = 0; i < serviceImageUrls.length; i += batchSize) {
      if (!context.mounted) break;

      final end = (i + batchSize).clamp(0, serviceImageUrls.length);
      final batch = serviceImageUrls.sublist(i, end);

      // Précharger le groupe actuel
      final futures = batch.map((url) => preloadServiceImage(url, context));
      await Future.wait(futures);

      // Petit délai entre les groupes pour éviter la surcharge
      if (i + batchSize < serviceImageUrls.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  // Précharger seulement les images visibles (optimisation)
  Future<void> preloadVisibleServiceImages(
    List<String> visibleImageUrls,
    BuildContext context,
  ) async {
    if (visibleImageUrls.isEmpty || !context.mounted) return;

    // Précharger seulement les 6 premières images (généralement visibles)
    final limitedUrls = visibleImageUrls.take(6).toList();

    for (final url in limitedUrls) {
      if (!context.mounted) break;
      await preloadServiceImage(url, context);
      // Petit délai entre chaque image pour éviter la surcharge
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // Obtenir le cache manager pour les services (pour CachedNetworkImage)
  CacheManager get servicesCacheManager => _servicesCacheManager;

  // Vider le cache
  Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }

  // Vider le cache des services
  Future<void> clearServicesCache() async {
    await _servicesCacheManager.emptyCache();
  }

  // Obtenir la taille du cache
  Future<int> getCacheSize() async {
    final files = await _cacheManager.getFileStream('').length;
    return files;
  }

  // Widget optimisé pour les images
  Widget buildOptimizedImage({
    required String imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final validUrl = getValidImageUrl(imageUrl);

    // Gérer les data URLs différemment
    if (validUrl.startsWith('data:image/')) {
      return _buildDataUrlImage(
        dataUrl: validUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder,
        errorWidget: errorWidget,
      );
    }

    // Gérer les URLs normales avec CachedNetworkImage
    return CachedNetworkImage(
      imageUrl: validUrl,
      width: width,
      height: height,
      fit: fit,
      cacheManager: _cacheManager,
      placeholder: placeholder != null
          ? (context, url) => placeholder
          : (context, url) => Container(
              width: width,
              height: height,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
      errorWidget: errorWidget != null
          ? (context, url, error) => errorWidget
          : (context, url, error) => Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.error, color: Colors.grey),
            ),
    );
  }

  // Widget pour les data URLs
  Widget _buildDataUrlImage({
    required String dataUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    try {
      // Extraire la partie base64 de la data URL
      final base64String = dataUrl.split(',')[1];
      final bytes = base64Decode(base64String);

      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ??
              Container(
                width: width,
                height: height,
                color: Colors.grey[300],
                child: const Icon(Icons.error, color: Colors.grey),
              );
        },
      );
    } catch (e) {
      print('❌ Erreur lors du décodage de la data URL: $e');
      return errorWidget ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.error, color: Colors.grey),
          );
    }
  }
}
