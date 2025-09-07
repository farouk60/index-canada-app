import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils.dart';
import '../image_cache_service.dart';

// Gestionnaire de chargement d'images pour tracking
class _ImageLoadingManager {
  static int _currentlyLoading = 0;
  
  static void startLoading() => _currentlyLoading++;
  static void stopLoading() => _currentlyLoading = _currentlyLoading > 0 ? _currentlyLoading - 1 : 0;
}

/// Widget qui tente plusieurs variantes Wix si la première échoue
class WixImageWithFallback extends StatefulWidget {
  final String image;
  final int index;
  const WixImageWithFallback(this.image, {Key? key, required this.index}) : super(key: key);

  @override
  State<WixImageWithFallback> createState() => _WixImageWithFallbackState();
}

class _WixImageWithFallbackState extends State<WixImageWithFallback> with AutomaticKeepAliveClientMixin {
  // Not final so we can regenerate variants when the image URL changes (e.g., language switch)
  late List<String> variants;
  int current = 0;
  bool _disposed = false;
  bool _variantsGenerated = false;

  @override
  bool get wantKeepAlive => true; // Garde le widget en vie pour éviter les recharges

  @override
  void initState() {
    super.initState();
    // Génération différée des variantes pour éviter de bloquer le thread principal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) {
        _generateVariants();
      }
    });
  }

  void _generateVariants() {
    if (_disposed || !mounted) return;
    
    try {
      variants = getWixImageVariants(widget.image);
      _variantsGenerated = true;
      
      if (widget.index < 3) {
        print('🖼️ WixImageWithFallback[${widget.index}] variants: ${variants.length}');
        print('🖼️ Variant[0]: ${variants[0]}');
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('🖼️ Error generating variants for index ${widget.index}: $e');
      if (mounted) {
        setState(() {
          variants = [];
          _variantsGenerated = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant WixImageWithFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the image URL changes (e.g., language switched), regenerate variants
    if (oldWidget.image != widget.image) {
      current = 0;
      _variantsGenerated = false;
      variants = [];
      // Regenerate variants for the new image
      _generateVariants();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ImageLoadingManager.stopLoading();
    super.dispose();
  }

  void _tryNextVariant() {
    if (!_disposed && mounted && current < variants.length - 1) {
      if (widget.index < 3) {
        print('🖼️ Trying next variant: ${current + 1}/${variants.length}');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) {
          setState(() {
            current++;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Requis pour AutomaticKeepAliveClientMixin
    
    if (_disposed) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey.shade300, Colors.grey.shade400],
          ),
        ),
        child: const Center(
          child: Icon(Icons.category, color: Colors.white, size: 50),
        ),
      );
    }

    // Attendre que les variantes soient générées
    if (!_variantsGenerated) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade200, Colors.blue.shade400],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.0,
          ),
        ),
      );
    }

    // Si aucune variante n'a pu être générée
    if (variants.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.blue.shade600],
          ),
        ),
        child: const Center(
          child: Icon(Icons.category, color: Colors.white, size: 50),
        ),
      );
    }

    return CachedNetworkImage(
      // Include image in the key to force a proper refresh when it changes
      key: ValueKey('wix_${widget.index}_${widget.image}_$current'),
      imageUrl: variants[current],
      cacheManager: ImageCacheService.instance.servicesCacheManager,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low, // Qualité plus basse pour vitesse
      fadeInDuration: const Duration(milliseconds: 200), // Animation plus rapide
      fadeOutDuration: const Duration(milliseconds: 50), // Transition plus rapide
      memCacheWidth: 400, // Limite la taille en mémoire pour les services
      memCacheHeight: 300,
      placeholder: (context, url) {
        _ImageLoadingManager.startLoading();
        if (!_disposed && widget.index < 3) {
          print('🖼️ Loading image[$current]: $url');
        }
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade200, Colors.blue.shade400],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.0,
            ),
          ),
        );
      },
      errorWidget: (context, url, error) {
        _ImageLoadingManager.stopLoading();
        if (!_disposed && widget.index < 3) {
          print('🖼️ Error loading image[$current]: $error');
        }
        
        // Essayer la variante suivante si disponible
        if (!_disposed && current < variants.length - 1) {
          _tryNextVariant();
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade200, Colors.blue.shade300],
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.0,
              ),
            ),
          );
        }
        
        // Toutes les variantes ont échoué
        if (!_disposed && widget.index < 3) {
          print('🖼️ All variants failed for image ${widget.index}');
        }
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade600],
            ),
          ),
          child: const Center(
            child: Icon(Icons.category, color: Colors.white, size: 50),
          ),
        );
      },
      imageBuilder: (context, imageProvider) {
        _ImageLoadingManager.stopLoading();
        if (!_disposed && widget.index < 3) {
          print('🖼️ ✅ Image loaded successfully for index ${widget.index}');
        }
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
