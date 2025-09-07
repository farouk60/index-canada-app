import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../data_service.dart';
import '../image_cache_service.dart';
import '../widgets/coupon_widget.dart';
import '../widgets/media_gallery_widget.dart';
import '../simple_phone.dart';
import '../services/favorite_service.dart';
import '../services/maps_service.dart';
import '../services/localization_service.dart';
import '../services/firebase_analytics_service.dart';
import '../widgets/language_selector.dart';
import 'add_review_page.dart';
import '../theme/app_theme.dart';
import '../widgets/full_screen_image_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils.dart';

class ProfessionnelDetailPage extends StatefulWidget {
  final Professionnel professionnel;

  const ProfessionnelDetailPage({super.key, required this.professionnel});

  @override
  State<ProfessionnelDetailPage> createState() =>
      _ProfessionnelDetailPageState();
}

class _ProfessionnelDetailPageState extends State<ProfessionnelDetailPage> {
  final LocalizationService _localizationService = LocalizationService();
  final FirebaseAnalyticsService _analytics = FirebaseAnalyticsService();
  List<Review> _reviews = [];
  bool _isLoadingReviews = true;
  String? _reviewsError;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _preloadGalleryImages();
    _loadFavoriteStatus();
    _trackProfessionalView();
  }

  // Tracker la vue du professionnel
  void _trackProfessionalView() async {
    await _analytics.trackProfessionalView(
      professionalId: widget.professionnel.id,
      professionalName: widget.professionnel.title,
      category: widget.professionnel.sousCategorie,
      city: widget.professionnel.ville,
      isSponsor: widget.professionnel.sponsor,
    );
    await _analytics.setCurrentScreen('professional_detail');
  }

  // Charger le statut favori depuis le stockage local
  void _loadFavoriteStatus() async {
    try {
      final favoriteService = FavoriteService.instance;
      final isFavorite = await favoriteService.isFavorite(
        widget.professionnel.id,
      );
      if (mounted) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
    } catch (e) {
      // Ignorer les erreurs de chargement du statut favori
      print('Erreur lors du chargement du statut favori: $e');
    }
  }

  // Basculer l'état d'un favori
  Future<void> _toggleFavorite() async {
    try {
      final favoriteService = FavoriteService.instance;
      final newFavoriteStatus = await favoriteService.toggleFavorite(
        widget.professionnel.id,
      );

      // Tracker l'action de favori
      await _analytics.trackFavoriteAction(
        professionalId: widget.professionnel.id,
        professionalName: widget.professionnel.title,
        isAdding: newFavoriteStatus,
      );

      if (mounted) {
        setState(() {
          _isFavorite = newFavoriteStatus;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newFavoriteStatus
                  ? _localizationService.tr('added_to_favorites')
                  : _localizationService.tr('removed_from_favorites'),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: newFavoriteStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Précharger les images de la galerie
  void _preloadGalleryImages() async {
    // Précharger après le premier frame pour éviter les erreurs de contexte
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final galleryImages = widget.professionnel.getAllGalleryImages();
      if (galleryImages.isEmpty) return;

      final count = galleryImages.length < 6 ? galleryImages.length : 6;
      for (int i = 0; i < count; i++) {
        final raw = galleryImages[i];
        if (raw.isEmpty) continue;
        final valid = getValidImageUrl(raw);
        String thumb = valid;
        if (valid.startsWith('wix:image://')) {
          final variants = getWixImageVariants(valid);
          if (variants.isNotEmpty) thumb = variants.first;
        }
        if (thumb.startsWith('http')) {
          final provider = CachedNetworkImageProvider(thumb);
          // fire-and-forget: warm up cache
          precacheImage(provider, context);
        }
      }
    });
  }

  Future<void> _loadReviews() async {
    try {
      final wixApi = DataService();
      final reviews = await wixApi.fetchReviews(widget.professionnel.id);
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reviewsError = e.toString();
          _isLoadingReviews = false;
        });
      }
    }
  }

  double _calculateAverageRating() {
    if (_reviews.isEmpty) return 0.0;
    final sum = _reviews.fold(0, (sum, review) => sum + review.rating);
    return sum / _reviews.length;
  }

  Widget _buildStarRating(double rating, {double size = 20}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: size);
        } else if (index < rating) {
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        } else {
          return Icon(Icons.star_outline, color: Colors.grey, size: size);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avgRating = _calculateAverageRating();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar avec image de profil
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppTheme.brandPrimary,
            foregroundColor: Colors.white,
            actions: [
              // Sélecteur de langue
              LanguageSelector(
                onLanguageChanged: (String languageCode) {
                  // Forcer la reconstruction de la page pour mettre à jour la langue
                  setState(() {
                    // La page sera reconstruite avec la nouvelle langue
                  });
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.professionnel.image.isNotEmpty
                      ? _openFullScreenGallery
                      : null,
                  child: widget.professionnel.image.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // DEBUG: Imprimer l'URL de l'image
                          Builder(
                            builder: (context) {
                              print('Image URL: ${widget.professionnel.image}');
                              print(
                                'Image is valid URL: ${Uri.tryParse(widget.professionnel.image) != null}',
                              );
                              return ImageCacheService().buildOptimizedImage(
                                imageUrl: widget.professionnel.image,
                                width: double.infinity,
                                height: 250,
                                fit: BoxFit.cover,
                                placeholder: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.person,
                                        size: 100,
                                        color: Colors.white,
                                      ),
                                      Text(
                                        'Image non trouvée\n${widget.professionnel.image}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 100,
                          color: Colors.white,
                        ),
                      ),
                ),
              ),
            ),
          ),
          // Contenu principal
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CTA rapide: Appeler, Itinéraire, Site web, Partager
                  _buildActionButtons(),
                  const SizedBox(height: 16),
                  // Informations principales
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.professionnel.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (widget.professionnel.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.professionnel.subtitle,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (widget.professionnel.address.isNotEmpty)
                            _buildInfoRow(
                              Icons.location_on,
                              _localizationService.tr('address'),
                              widget.professionnel.address,
                            ),
                          if (widget.professionnel.ville.isNotEmpty)
                            _buildInfoRow(
                              Icons.location_city,
                              _localizationService.tr('city'),
                              widget.professionnel.ville,
                            ),
                          if (widget.professionnel.numroDeTlphone.isNotEmpty)
                            _buildInfoRow(
                              Icons.phone,
                              _localizationService.tr('phone'),
                              widget.professionnel.numroDeTlphone,
                            ),
                          if (widget.professionnel.email.isNotEmpty)
                            _buildInfoRow(
                              Icons.email,
                              _localizationService.tr('email'),
                              widget.professionnel.email,
                            ),
                          if (widget.professionnel.website.isNotEmpty)
                            _buildInfoRow(
                              Icons.language,
                              _localizationService.tr('website'),
                              widget.professionnel.website,
                            ),
                          // Section réseaux sociaux
                          if (widget.professionnel.facebook.isNotEmpty ||
                              widget.professionnel.instagram.isNotEmpty ||
                              widget.professionnel.linkedin.isNotEmpty ||
                              widget.professionnel.whatsapp.isNotEmpty ||
                              widget.professionnel.tiktok.isNotEmpty ||
                              widget.professionnel.youtube.isNotEmpty)
                            _buildSocialMediaSection(),
                          if (widget.professionnel.sponsor)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.brandSecondary, AppTheme.brandTertiary],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.white, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    _localizationService.tr('recommended_professional'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Widget coupon complet si disponible
                  CouponWidget(
                    professionnel: widget.professionnel,
                    isCompact: false,
                  ),

                  // Galerie d'images avec gestion d'erreurs améliorée
                  if (widget.professionnel.getAllGalleryImages().isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // DEBUG: Logs pour diagnostiquer
                        Builder(
                          builder: (context) {
                            print('=== ProfessionnelDetailPage DEBUG ===');
                            print(
                              'Professionnel: ${widget.professionnel.title}',
                            );
                            print(
                              'Nombre d\'images: ${widget.professionnel.getAllGalleryImages().length}',
                            );
                            print(
                              'Images: ${widget.professionnel.getAllGalleryImages().map((img) => img.substring(0, img.length.clamp(0, 50))).toList()}',
                            );
                            print('====================================');
                            return Container();
                          },
                        ),
                        Text(
                          _localizationService.tr('image_gallery'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        MediaGalleryWidget(
                          professionnel: widget.professionnel,
                          imageHeight: 150,
                          imageWidth: 200,
                        ),
                      ],
                    ),
                  if (widget.professionnel.getAllGalleryImages().isNotEmpty)
                    const SizedBox(height: 16),

                  // Section des avis
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_localizationService.tr('client_reviews')} (${_reviews.length})',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddReviewPage(
                                        professionnelId:
                                            widget.professionnel.id,
                                      ),
                                    ),
                                  );
                                  if (result == true) {
                                    // Recharger immédiatement puis une seconde fois après un court délai
                                    _loadReviews();
                                    Future.delayed(const Duration(seconds: 2), () {
                                      if (mounted) {
                                        _loadReviews();
                                      }
                                    });
                                  }
                                },
                                icon: const Icon(Icons.add),
                                label: Text(
                                  _localizationService.tr('add_review'),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brandPrimary,
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ],
                          ),
                          if (_reviews.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _buildStarRating(avgRating, size: 24),
                                const SizedBox(width: 8),
                                Text(
                                  '${avgRating.toStringAsFixed(1)}/5',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_isLoadingReviews)
                            const Center(child: CircularProgressIndicator())
                          else if (_reviewsError != null)
                            Center(
                              child: Text(
                                '${_localizationService.tr('error')}: $_reviewsError',
                                style: TextStyle(color: Colors.red.shade600),
                              ),
                            )
                          else if (_reviews.isEmpty)
                            Center(
                              child: Text(
                                _localizationService.tr('no_reviews_first'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _reviews.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final review = _reviews[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              review.auteurNom,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          _buildStarRating(
                                            review.rating.toDouble(),
                                          ),
                                        ],
                                      ),
                                      if (review.title.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          review.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                      if (review.message.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          review.message,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleFavorite,
        backgroundColor: _isFavorite ? Colors.red : Colors.grey,
        child: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          color: Colors.white,
        ),
      ),
    );
  }

  void _openFullScreenGallery() {
    final p = widget.professionnel;
    final images = p.getAllGalleryImages();
    // Construire une liste avec la photo de profil en premier, puis la galerie, sans doublons
    final List<String> effectiveImages = [];
    if (p.image.isNotEmpty) {
      effectiveImages.add(p.image);
    }
    for (final url in images) {
      if (url.isNotEmpty && url != p.image) {
        effectiveImages.add(url);
      }
    }
    // Si aucune image du tout, garder liste vide (le viewer gère l'état vide)

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageGallery.withImages(
          images: effectiveImages,
          initialIndex: 0, // on a tapé la photo de profil, donc index 0
        ),
      ),
    );
  }

  // Boutons d'action principaux sous l'en-tête
  Widget _buildActionButtons() {
    final hasPhone = widget.professionnel.numroDeTlphone.isNotEmpty;
    final hasAddress = widget.professionnel.address.isNotEmpty;
    final hasWebsite = widget.professionnel.website.isNotEmpty;
    final lang = _localizationService.currentLanguage;

    String t(String fr, String en) => lang == 'fr' ? fr : en;

  return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: hasPhone
              ? () async {
                  await _analytics.trackPhoneCall(
                    professionalId: widget.professionnel.id,
                    professionalName: widget.professionnel.title,
                  );
                  SimplePhoneCall.call(widget.professionnel.numroDeTlphone);
                }
              : null,
          icon: const Icon(Icons.phone),
          label: Text(t('Appeler', 'Call')),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasPhone ? Colors.green.shade600 : Colors.grey,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: hasAddress ? () => _openMaps(widget.professionnel.address) : null,
          icon: const Icon(Icons.directions),
          label: Text(t('Itinéraire', 'Directions')),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasAddress ? AppTheme.brandPrimary : Colors.grey,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: hasWebsite ? () => _openWebsite(widget.professionnel.website) : null,
          icon: const Icon(Icons.language),
          label: Text(t('Site web', 'Website')),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasWebsite ? AppTheme.brandSecondary : Colors.grey,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
  ),
      ],
    );
  }

  // Ouvrir Google Maps avec l'adresse
  Future<void> _openMaps(String address) async {
    try {
      // Tracker la navigation
      await _analytics.trackMapNavigation(
        professionalId: widget.professionnel.id,
        professionalName: widget.professionnel.title,
        address: address,
      );

      final mapsService = MapsService.instance;
      final success = await mapsService.openNativeMaps(address);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('network_error')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Ouvrir le site web du professionnel
  Future<void> _openWebsite(String website) async {
    try {
      // Tracker l'ouverture du site web
      await _analytics.trackWebsiteClick(
        professionalId: widget.professionnel.id,
        professionalName: widget.professionnel.title,
        website: website,
      );

      // Formatter l'URL si elle ne commence pas par http/https
      String finalUrl = website;
      if (!website.startsWith('http://') && !website.startsWith('https://')) {
        finalUrl = 'https://$website';
      }

      final Uri url = Uri.parse(finalUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'Impossible d\'ouvrir le site web';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizationService.currentLanguage == 'en'
                  ? 'Could not open website'
                  : 'Impossible d\'ouvrir le site web',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.brandPrimary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                // Si c'est un numéro de téléphone, on le rend cliquable
                if (label == _localizationService.tr('phone'))
                  ClickToCall(
                    phoneNumber: value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    onCallInitiated: () async {
                      await _analytics.trackPhoneCall(
                        professionalId: widget.professionnel.id,
                        professionalName: widget.professionnel.title,
                      );
                    },
                  )
                // Si c'est une adresse, on la rend cliquable pour ouvrir Maps
                else if (label == _localizationService.tr('address'))
                  GestureDetector(
                    onTap: () => _openMaps(value),
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.brandPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                // Si c'est un site web, on le rend cliquable
                else if (label == _localizationService.tr('website'))
                  GestureDetector(
                    onTap: () => _openWebsite(value),
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.brandPrimary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                else
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Section des réseaux sociaux - petits carrés avec logos seulement
  Widget _buildSocialMediaSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (widget.professionnel.facebook.isNotEmpty)
            _buildSocialIcon(
              Icons.facebook,
              Colors.blue.shade600,
              widget.professionnel.facebook,
              'Facebook',
            ),
          if (widget.professionnel.instagram.isNotEmpty)
            _buildSocialIcon(
              Icons.camera_alt,
              Colors.pink.shade400,
              widget.professionnel.instagram,
              'Instagram',
            ),
          if (widget.professionnel.linkedin.isNotEmpty)
            _buildSocialIcon(
              Icons.business,
              Colors.blue.shade800,
              widget.professionnel.linkedin,
              'LinkedIn',
            ),
          if (widget.professionnel.whatsapp.isNotEmpty)
            _buildSocialIcon(
              Icons.chat,
              Colors.green.shade600,
              widget.professionnel.whatsapp,
              'WhatsApp',
            ),
          if (widget.professionnel.tiktok.isNotEmpty)
            _buildSocialIcon(
              Icons.music_note,
              Colors.black,
              widget.professionnel.tiktok,
              'TikTok',
            ),
          if (widget.professionnel.youtube.isNotEmpty)
            _buildSocialIcon(
              Icons.play_circle_fill,
              Colors.red.shade600,
              widget.professionnel.youtube,
              'YouTube',
            ),
        ],
      ),
    );
  }

  // Petit carré avec logo de réseau social
  Widget _buildSocialIcon(
    IconData icon,
    Color color,
    String url,
    String platform,
  ) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _openSocialLink(url, platform),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // Ouvrir un lien de réseau social
  void _openSocialLink(String url, String platform) async {
    try {
      // Formater l'URL selon la plateforme
      String finalUrl = _formatSocialUrl(url, platform);

      // Créer l'URI
      final Uri uri = Uri.parse(finalUrl);

      // Vérifier si l'URL peut être lancée
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Ouvrir dans l'app externe
        );
      } else {
        // Si l'URL ne peut pas être lancée, afficher une erreur
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Impossible d\'ouvrir $platform'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'ouverture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Formater l'URL selon la plateforme
  String _formatSocialUrl(String url, String platform) {
    // Si l'URL est déjà complète, la retourner telle quelle
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // Formater selon la plateforme
    switch (platform.toLowerCase()) {
      case 'facebook':
        // Si c'est juste un nom d'utilisateur, créer l'URL Facebook
        if (!url.contains('facebook.com')) {
          return 'https://www.facebook.com/$url';
        }
        break;
      case 'instagram':
        // Si c'est juste un nom d'utilisateur, créer l'URL Instagram
        if (!url.contains('instagram.com')) {
          // Supprimer le @ s'il est présent
          String username = url.replaceFirst('@', '');
          return 'https://www.instagram.com/$username';
        }
        break;
      case 'linkedin':
        // Si c'est juste un nom d'utilisateur, créer l'URL LinkedIn
        if (!url.contains('linkedin.com')) {
          return 'https://www.linkedin.com/in/$url';
        }
        break;
      case 'whatsapp':
        // Si c'est juste un numéro, créer l'URL WhatsApp
        if (!url.contains('wa.me') && !url.contains('whatsapp.com')) {
          // Supprimer les espaces et caractères spéciaux
          String phone = url.replaceAll(RegExp(r'[^\d+]'), '');
          return 'https://wa.me/$phone';
        }
        break;
      case 'tiktok':
        // Si c'est juste un nom d'utilisateur, créer l'URL TikTok
        if (!url.contains('tiktok.com')) {
          // Supprimer le @ s'il est présent
          String username = url.replaceFirst('@', '');
          return 'https://www.tiktok.com/@$username';
        }
        break;
      case 'youtube':
        // Si c'est juste un nom d'utilisateur, créer l'URL YouTube
        if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
          // Si ça commence par @, c'est un handle YouTube
          if (url.startsWith('@')) {
            return 'https://www.youtube.com/$url';
          }
          // Sinon, c'est peut-être un nom de chaîne
          return 'https://www.youtube.com/c/$url';
        }
        break;
    }

    // Si aucun format spécifique, ajouter https://
    return 'https://$url';
  }

  @override
  void dispose() {
    // Nettoyer les ressources pour éviter les fuites mémoire
    super.dispose();
  }
}
