import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Widget d'image optimisé avec timeout court pour éviter les spinners infinis
class FastImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration timeout;

  const FastImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.timeout = const Duration(
      seconds: 8,
    ), // Timeout plus généreux par défaut
  });

  @override
  State<FastImageWidget> createState() => _FastImageWidgetState();
}

class _FastImageWidgetState extends State<FastImageWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Détermine si l'image est une data URL
  bool _isDataUrl(String url) {
    return url.startsWith('data:image/');
  }

  /// Widget d'erreur par défaut
  Widget _defaultErrorWidget() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Icon(Icons.person, color: Colors.grey, size: 24),
      ),
    );
  }

  /// Widget placeholder par défaut
  Widget _defaultPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Supprimer le timeout pour les logos de partenaires
    // Le timeout est maintenu pour des cas spécifiques mais ne force plus l'erreur
    // if (_hasTimedOut) {
    //   return widget.errorWidget ?? _defaultErrorWidget();
    // }

    if (widget.imageUrl.isEmpty) {
      return widget.errorWidget ?? _defaultErrorWidget();
    }

    if (_isDataUrl(widget.imageUrl)) {
      // Traitement des data URLs (base64)
      try {
        final String base64String = widget.imageUrl.split(',')[1];
        final Uint8List imageBytes = base64Decode(base64String);

        return Image.memory(
          imageBytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) {
            return widget.errorWidget ?? _defaultErrorWidget();
          },
        );
      } catch (e) {
        return widget.errorWidget ?? _defaultErrorWidget();
      }
    } else {
      // Traitement des URLs web normales avec timeout
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (context, url) =>
            widget.placeholder ?? _defaultPlaceholder(),
        errorWidget: (context, url, error) {
          return widget.errorWidget ?? _defaultErrorWidget();
        },
        // Optimisations pour le chargement rapide
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 100),
        memCacheWidth: widget.width?.toInt(),
        memCacheHeight: widget.height?.toInt(),
        maxWidthDiskCache: 200, // Limiter la taille sur disque
        maxHeightDiskCache: 200,
      );
    }
  }
}
