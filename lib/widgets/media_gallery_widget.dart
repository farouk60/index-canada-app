import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models.dart';
import '../utils.dart';
import 'full_screen_image_gallery.dart';
import 'fast_image_widget.dart';
import '../services/data_saver_service.dart';

/// Widget pour afficher une galerie d'images avec gestion des erreurs
/// Utilise maintenant les champs individuels du professionnel
class MediaGalleryWidget extends StatefulWidget {
  final Professionnel
  professionnel; // Utilise directement l'objet professionnel
  final double imageHeight;
  final double imageWidth;
  final EdgeInsets margin;
  final BorderRadius borderRadius;

  const MediaGalleryWidget({
    Key? key,
    required this.professionnel,
    this.imageHeight = 150.0,
    this.imageWidth = 200.0,
    this.margin = const EdgeInsets.only(right: 8.0),
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
  }) : super(key: key);

  @override
  State<MediaGalleryWidget> createState() => _MediaGalleryWidgetState();
}

class _MediaGalleryWidgetState extends State<MediaGalleryWidget> {
  late final List<String> _galleryImages;
  bool _prefetched = false;

  @override
  void initState() {
    super.initState();
    _galleryImages = widget.professionnel.getAllGalleryImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefetched) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prefetchThumbnails();
      });
      _prefetched = true;
    }
  }

  Future<void> _prefetchThumbnails() async {
    final canPrefetch = await DataSaverService.instance.shouldPrefetch();
    if (!canPrefetch) return;

    final int dynamicCount = _computePrefetchCount(context);
    final count = _galleryImages.length < dynamicCount ? _galleryImages.length : dynamicCount;
    for (int i = 0; i < count; i++) {
      final url = _resolveThumbnailUrl(_galleryImages[i]);
      if (url.startsWith('http')) {
        final provider = CachedNetworkImageProvider(url);
        precacheImage(provider, context);
      }
    }
  }

  int _computePrefetchCount(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final width = mq.size.width;
    if (dpr >= 3.0 || width >= 1080) return 10; // haut de gamme
    if (dpr >= 2.0 || width >= 720) return 6;   // milieu de gamme
    return 4;                                    // entrée de gamme
  }

  @override
  Widget build(BuildContext context) {
    final galleryImages = _galleryImages;

    if (galleryImages.isEmpty) {
      return SizedBox(
        height: widget.imageHeight,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Aucune image disponible',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.imageHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: galleryImages.length,
        cacheExtent: widget.imageWidth * 3, // prefetch ~3 items ahead
        itemBuilder: (context, index) {
          final imageUrl = galleryImages[index];

          return GestureDetector(
            onTap: () {
              // Ouvrir l'album photo en plein écran
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => FullScreenImageGallery(
                    professionnel: widget.professionnel,
                    initialIndex: index,
                  ),
                ),
              );
            },
            child: Container(
              margin: widget.margin,
              width: widget.imageWidth,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: widget.borderRadius,
                child: _buildImageWidget(imageUrl),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget();
    }
    final thumbUrl = _resolveThumbnailUrl(imageUrl);
    return FastImageWidget(
      imageUrl: thumbUrl,
      width: widget.imageWidth,
      height: widget.imageHeight,
      fit: BoxFit.cover,
      placeholder: Container(
        width: widget.imageWidth,
        height: widget.imageHeight,
        color: Colors.grey[200],
        child: const Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      errorWidget: _buildErrorWidget(),
      timeout: const Duration(seconds: 8),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: widget.imageWidth,
      height: widget.imageHeight,
      color: Colors.grey.shade200,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'Image\nindisponible',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _resolveThumbnailUrl(String imageUrl) {
    if (imageUrl.isEmpty) return imageUrl;
    final valid = getValidImageUrl(imageUrl);
    if (valid.startsWith('wix:image://')) {
      // Adapter au device: vignettes ~ (width x height) réelles du widget
      final targetW = (widget.imageWidth * MediaQuery.of(context).devicePixelRatio).round();
      final targetH = (widget.imageHeight * MediaQuery.of(context).devicePixelRatio).round();
      return getWixFittedUrl(valid, targetW: targetW, targetH: targetH, quality: 75);
    }
    return valid;
  }
}
