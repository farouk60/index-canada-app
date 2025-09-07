import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Mixin pour optimiser les performances des pages avec beaucoup d'images
mixin ImageOptimizationMixin<T extends StatefulWidget> on State<T> {
  /// Précharge une image de manière optimisée
  Future<void> optimizedPrecacheImage(String imageUrl) async {
    if (!mounted) return;

    try {
      await precacheImage(CachedNetworkImageProvider(imageUrl), context);
    } catch (e) {
      // Ignorer les erreurs de préchargement
    }
  }

  /// Précharge une liste d'images par batch pour éviter de bloquer l'UI
  Future<void> batchPrecacheImages(
    List<String> imageUrls, {
    int batchSize = 3,
    Duration delayBetweenBatches = const Duration(milliseconds: 100),
  }) async {
    for (int i = 0; i < imageUrls.length; i += batchSize) {
      if (!mounted) return;

      final batch = imageUrls.skip(i).take(batchSize);

      // Précharger le batch actuel en parallèle
      await Future.wait(batch.map((url) => optimizedPrecacheImage(url)));

      // Petite pause entre les batches
      if (i + batchSize < imageUrls.length) {
        await Future.delayed(delayBetweenBatches);
      }
    }
  }

  /// Widget optimisé pour les images avec des paramètres de performance
  Widget buildOptimizedImage({
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    PlaceholderWidgetBuilder? placeholder,
    LoadingErrorWidgetBuilder? errorWidget,
    BorderRadius? borderRadius,
  }) {
    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      // Optimisations de performance
      memCacheWidth: (width ?? 300).toInt(),
      memCacheHeight: (height ?? 300).toInt(),
      maxWidthDiskCache: 800,
      maxHeightDiskCache: 800,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholderFadeInDuration: const Duration(milliseconds: 100),
      placeholder:
          placeholder ??
          (context, url) => Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: borderRadius,
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
          ),
      errorWidget:
          errorWidget ??
          (context, url, error) => Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: borderRadius,
            ),
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius, child: image);
    }

    return image;
  }
}
