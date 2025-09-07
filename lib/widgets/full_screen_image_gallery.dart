import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../utils.dart';
import '../services/data_saver_service.dart';

/// Widget pour afficher une galerie d'images en plein écran
/// Permet de naviguer entre les images comme un album photo
class FullScreenImageGallery extends StatefulWidget {
  final Professionnel? professionnel;
  final List<String>? images;
  final int initialIndex;

  const FullScreenImageGallery({
    Key? key,
    required this.professionnel,
    this.initialIndex = 0,
  }) : images = null,
       super(key: key);

  const FullScreenImageGallery.withImages({
    Key? key,
    required this.images,
    this.initialIndex = 0,
  }) : professionnel = null,
       super(key: key);

  @override
  State<FullScreenImageGallery> createState() => _FullScreenImageGalleryState();
}

class _FullScreenImageGalleryState extends State<FullScreenImageGallery> {
  late PageController _pageController;
  late int _currentIndex;
  late List<String> _images;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();

    // Récupérer les images depuis le professionnel ou depuis la liste fournie
    if (widget.professionnel != null) {
      _images = widget.professionnel!.getAllGalleryImages();
    } else if (widget.images != null) {
      _images = widget.images!;
    } else {
      _images = [];
    }

  // Empêcher une borne supérieure négative quand la liste est vide
  final maxIndex = _images.isEmpty ? 0 : _images.length - 1;
  _currentIndex = widget.initialIndex.clamp(0, maxIndex);
  _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Aucune image disponible',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Galerie d'images
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _precacheAdjacent(index);
            },
            allowImplicitScrolling: true,
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _showUI = !_showUI;
                  });
                },
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(child: _buildImageWidget(_images[index])),
                ),
              );
            },
          ),

          // Interface utilisateur (barre supérieure et indicateurs)
          AnimatedOpacity(
            opacity: _showUI ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Column(
              children: [
                // Barre supérieure avec gradient léger
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromARGB(120, 0, 0, 0),
                        Colors.transparent,
                      ],
                      stops: [0.0, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Text(
                            '${_currentIndex + 1} / ${_images.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // Espace vide pour maintenir l'alignement centré du texte
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Indicateurs de position avec fond léger
                if (_images.length > 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        _images.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: index == _currentIndex ? 12 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == _currentIndex
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Boutons de navigation (gauche et droite)
          if (_images.length > 1 && _showUI)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _currentIndex > 0 ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _currentIndex > 0 ? _previousImage : null,
                    ),
                  ),
                ),
              ),
            ),
          if (_images.length > 1 && _showUI)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _currentIndex < _images.length - 1 ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _currentIndex < _images.length - 1
                          ? _nextImage
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(String imageUrl) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget();
    }

    // Pour les images Wix, tester d'abord l'URL originale directe
    if (imageUrl.startsWith('wix:image://')) {
      final regex = RegExp(r'wix:image://v1/([^/]+)');
      final match = regex.firstMatch(imageUrl);

      if (match != null) {
        final wixId = match.group(1);
        final originalUrl = 'https://static.wixstatic.com/media/$wixId';

        return Image.network(
          originalUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              // Image chargée avec succès - gestion des images transparentes (PNG)
              if (imageUrl.toLowerCase().contains('.png')) {
                return Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: child,
                  ),
                );
              }
              return child;
            }
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chargement image ${_currentIndex + 1}...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Fallback vers l'approche haute qualité
            return _buildHighQualityImage(imageUrl);
          },
        );
      }
    }

    return _buildHighQualityImage(imageUrl);
  }

  Widget _buildHighQualityImage(String imageUrl) {
    // Utiliser des dimensions adaptées à l'écran pour limiter le poids
    final mq = MediaQuery.of(context);
    final maxSide = (mq.size.shortestSide * mq.devicePixelRatio).clamp(720.0, 1920.0).round();

    String fittedUrl;
    if (imageUrl.startsWith('wix:image://')) {
      fittedUrl = getWixFittedUrl(imageUrl, targetW: maxSide, targetH: maxSide, quality: 85);
    } else {
      fittedUrl = getHighQualityImageUrl(imageUrl);
    }
    return _buildNetworkImage(fittedUrl);
  }

  Widget _buildNetworkImage(String validImageUrl) {
    if (validImageUrl.startsWith('data:image')) {
      // Data URL (base64)
      try {
        final base64String = validImageUrl.split(',').last;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget(
              'Erreur: Image trop lourde ou inaccessible',
            );
          },
        );
      } catch (e) {
        return _buildErrorWidget('Erreur: Format base64 invalide');
      }
    } else if (validImageUrl.startsWith('http://') ||
        validImageUrl.startsWith('https://')) {
      // URL réseau
      return Image.network(
        validImageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            // Image chargée avec succès - gestion des images transparentes (PNG)
            if (validImageUrl.toLowerCase().contains('.png')) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              );
            }
            return child;
          }

          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget('Erreur réseau: ${error.toString()}');
        },
      );
    } else {
      // Format d'URL non reconnu
      return _buildErrorWidget(
        'Format d\'URL non reconnu: ${validImageUrl.substring(0, 30)}...',
      );
    }
  }

  Widget _buildErrorWidget([String? debugInfo]) {
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.grey.shade800,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Image indisponible',
            style: TextStyle(color: Colors.grey, fontSize: 18),
          ),
          if (debugInfo != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                debugInfo,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _previousImage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextImage() {
    if (_currentIndex < _images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _precacheAdjacent(int index) async {
    // Respecter le mode économie de données
    final canPrefetch = await DataSaverService.instance.shouldPrefetch();
    if (!canPrefetch) return;

    final candidates = <int>{};
    if (index - 1 >= 0) candidates.add(index - 1);
    if (index + 1 < _images.length) candidates.add(index + 1);

    for (final i in candidates) {
      final url = getHighQualityImageUrl(_images[i]);
      if (url.startsWith('http')) {
        // Utiliser ImageProvider pour alimenter le cache
        final provider = NetworkImage(url);
        // ignore: use_build_context_synchronously
        if (mounted) precacheImage(provider, context);
      }
    }
  }
}
