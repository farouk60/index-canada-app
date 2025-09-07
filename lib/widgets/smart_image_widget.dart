import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../utils.dart';

/// Widget intelligent pour afficher des images
/// Peut gérer les data URLs (base64) et les URLs web normales
class SmartImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  // Cache manager personnalisé avec timeout plus court
  static final _cacheManager = CacheManager(
    Config(
      'smartImageCache',
      stalePeriod: const Duration(hours: 24),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'smartImageCache'),
      fileSystem: IOFileSystem('smartImageCache'),
    ),
  );

  const SmartImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// Détermine si l'image est une data URL
  bool _isDataUrl(String url) {
    return url.startsWith('data:image/');
  }

  /// Détermine si l'image est une URL Wix
  bool _isWixUrl(String url) {
    return url.startsWith('wix:image://');
  }

  /// Widget d'erreur par défaut
  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }

  /// Widget placeholder par défaut
  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // DEBUG: Afficher les infos sur l'image
    print(
      '🖼️ SmartImageWidget -> URL reçue: ${imageUrl.substring(0, imageUrl.length.clamp(0, 100))}...',
    );
    print('🖼️ SmartImageWidget -> Est vide: ${imageUrl.isEmpty}');
    print('🖼️ SmartImageWidget -> Est data URL: ${_isDataUrl(imageUrl)}');
    print('🖼️ SmartImageWidget -> Est Wix URL: ${_isWixUrl(imageUrl)}');

    if (imageUrl.isEmpty) {
      print('❌ SmartImageWidget -> Image vide, affichage erreur');
      return errorWidget ?? _defaultErrorWidget();
    }

    if (_isDataUrl(imageUrl)) {
      // Traitement des data URLs (base64)
      try {
        print('🔄 SmartImageWidget -> Traitement data URL...');
        final String base64String = imageUrl.split(',')[1];
        final Uint8List imageBytes = base64Decode(base64String);
        print(
          '✅ SmartImageWidget -> Data URL décodée: ${imageBytes.length} bytes',
        );

        return Image.memory(
          imageBytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            print('❌ Erreur affichage image data URL: $error');
            return errorWidget ?? _defaultErrorWidget();
          },
        );
      } catch (e) {
        print('❌ Erreur décodage data URL: $e');
        return errorWidget ?? _defaultErrorWidget();
      }
    } else if (_isWixUrl(imageUrl)) {
      // Afficher l'image Wix réellement via l'URL convertie
      final converted = getValidImageUrl(imageUrl);
      print('🔄 SmartImageWidget -> URL Wix convertie: $converted');
      return CachedNetworkImage(
        imageUrl: converted,
        width: width,
        height: height,
        fit: fit,
        cacheManager: _cacheManager,
        placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
        errorWidget: (context, url, error) => errorWidget ?? _defaultErrorWidget(),
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
      );
    } else {
      // Traitement des URLs web normales
      print('🔄 SmartImageWidget -> Traitement URL web: $imageUrl');
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        // Utiliser notre cache manager personnalisé
        cacheManager: _cacheManager,
        // Configuration des timeouts
        httpHeaders: const {
          'Cache-Control': 'max-age=3600', // 1 heure de cache
        },
        placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
        errorWidget: (context, url, error) {
          print('❌ Erreur chargement image réseau: $url');
          print('   Erreur: $error');
          return errorWidget ?? _defaultErrorWidget();
        },
        // Timeout réduit pour éviter les attentes infinies
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
      );
    }
  }
}
