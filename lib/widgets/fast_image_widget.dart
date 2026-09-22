import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Image réseau ou base64 avec cache et états de chargement prévisibles.
class FastImageWidget extends StatelessWidget {
  const FastImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  bool _isDataUrl(String url) => url.startsWith('data:image/');

  /// Widget d'erreur par défaut
  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
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
      width: width,
      height: height,
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
    if (imageUrl.isEmpty) {
      return errorWidget ?? _defaultErrorWidget();
    }

    if (_isDataUrl(imageUrl)) {
      try {
        final separatorIndex = imageUrl.indexOf(',');
        if (separatorIndex < 0 || separatorIndex == imageUrl.length - 1) {
          return errorWidget ?? _defaultErrorWidget();
        }
        final base64String = imageUrl.substring(separatorIndex + 1);
        final Uint8List imageBytes = base64Decode(base64String);

        return Image.memory(
          imageBytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ?? _defaultErrorWidget();
          },
        );
      } on FormatException {
        return errorWidget ?? _defaultErrorWidget();
      }
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
      errorWidget: (context, url, error) =>
          errorWidget ?? _defaultErrorWidget(),
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 100),
      memCacheWidth: width?.toInt(),
      memCacheHeight: height?.toInt(),
      maxWidthDiskCache: 200,
      maxHeightDiskCache: 200,
    );
  }
}
