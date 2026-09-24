import 'dart:async';

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
  final String sourcePlacement;
  final FirebaseAnalyticsService? analyticsService;
  final DataService? dataService;
  final Future<bool> Function(String phoneNumber)? phoneLauncher;
  final Future<bool> Function(String address)? mapsLauncher;
  final Future<bool> Function(Uri uri)? websiteLauncher;

  const ProfessionnelDetailPage({
    super.key,
    required this.professionnel,
    this.sourcePlacement = 'detail',
    this.analyticsService,
    this.dataService,
    this.phoneLauncher,
    this.mapsLauncher,
    this.websiteLauncher,
  });

  @override
  State<ProfessionnelDetailPage> createState() =>
      _ProfessionnelDetailPageState();
}

class _ProfessionnelDetailPageState extends State<ProfessionnelDetailPage> {
  final LocalizationService _localizationService = LocalizationService();
  late final FirebaseAnalyticsService _analytics;
  late final DataService _dataService;
  List<Review> _reviews = [];
  bool _isLoadingReviews = true;
  String? _reviewsError;
  bool _isFavorite = false;
  int _reviewsLoadGeneration = 0;
  int _favoriteLoadGeneration = 0;
  Future<void> _favoriteWriteQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _analytics = widget.analyticsService ?? FirebaseAnalyticsService();
    _dataService = widget.dataService ?? DataService();
    _loadReviews();
    _preloadGalleryImages();
    _loadFavoriteStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _trackProfessionalView();
    });
  }

  // Tracker la vue du professionnel
  void _trackProfessionalView() {
    _runAnalytics(
      () => _analytics.trackProfessionalView(
        professionalId: widget.professionnel.id,
        placement: widget.sourcePlacement,
        locale: _localizationService.currentLanguage,
      ),
    );
    _runAnalytics(() => _analytics.setCurrentScreen('professional_detail'));
  }

  void _runAnalytics(Future<void> Function() event) {
    try {
      unawaited(event().catchError((Object _) {}));
    } catch (_) {
      // La télémétrie ne doit jamais affecter le parcours principal.
    }
  }

  // Charger le statut favori depuis le stockage local
  Future<void> _loadFavoriteStatus() async {
    final loadGeneration = ++_favoriteLoadGeneration;
    try {
      final favoriteService = FavoriteService.instance;
      final isFavorite = await favoriteService.isFavorite(
        widget.professionnel.id,
      );
      if (mounted && loadGeneration == _favoriteLoadGeneration) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
    } catch (_) {
      // Ignorer les erreurs de chargement du statut favori
    }
  }

  // Basculer l'état d'un favori
  Future<void> _toggleFavorite() {
    ++_favoriteLoadGeneration;
    final operation = _favoriteWriteQueue.then<void>((_) async {
      await _performFavoriteToggle();
    });
    _favoriteWriteQueue = operation;
    return operation;
  }

  Future<void> _performFavoriteToggle() async {
    try {
      final favoriteService = FavoriteService.instance;
      final newFavoriteStatus = await favoriteService.toggleFavorite(
        widget.professionnel.id,
      );

      _runAnalytics(
        () => _analytics.trackFavoriteAction(
          professionalId: widget.professionnel.id,
          isAdding: newFavoriteStatus,
        ),
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
    } catch (_) {
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
    if (!mounted) return;

    final loadGeneration = ++_reviewsLoadGeneration;
    setState(() {
      _isLoadingReviews = true;
      _reviewsError = null;
    });

    try {
      final reviews = await _dataService.fetchReviews(widget.professionnel.id);
      if (mounted && loadGeneration == _reviewsLoadGeneration) {
        setState(() {
          _reviews = reviews;
          _reviewsError = null;
          _isLoadingReviews = false;
        });
      }
    } catch (_) {
      if (mounted && loadGeneration == _reviewsLoadGeneration) {
        setState(() {
          _reviewsError = 'loading_error';
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

  String _localized(String french, String english) {
    return _localizationService.currentLanguage == 'en' ? english : french;
  }

  double get _displayRating {
    if (_reviews.isNotEmpty) return _calculateAverageRating();
    return widget.professionnel.averageRating;
  }

  int get _displayReviewCount {
    if (_reviews.isNotEmpty) return _reviews.length;
    return widget.professionnel.reviewCount;
  }

  Widget _buildStarRating(double rating, {double size = 20}) {
    final label = _localized(
      'Note ${rating.toStringAsFixed(1)} sur 5',
      'Rating ${rating.toStringAsFixed(1)} out of 5',
    );

    return Semantics(
      label: label,
      readOnly: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            if (index < rating.floor()) {
              return Icon(
                Icons.star_rounded,
                color: const Color(0xFFE09B16),
                size: size,
              );
            } else if (index < rating) {
              return Icon(
                Icons.star_half_rounded,
                color: const Color(0xFFE09B16),
                size: size,
              );
            } else {
              return Icon(
                Icons.star_outline_rounded,
                color: Theme.of(context).colorScheme.outline,
                size: size,
              );
            }
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avgRating = _displayRating;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar avec image de profil
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppTheme.brandPrimary,
            foregroundColor: Colors.white,
            title: Text(
              widget.professionnel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
              Semantics(
                button: true,
                toggled: _isFavorite,
                label: _localized(
                  _isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  _isFavorite ? 'Remove from favorites' : 'Add to favorites',
                ),
                child: IconButton(
                  onPressed: _toggleFavorite,
                  tooltip: _localized(
                    _isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    _isFavorite ? 'Remove from favorites' : 'Add to favorites',
                  ),
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
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
                child: Semantics(
                  button: widget.professionnel.image.isNotEmpty,
                  label: widget.professionnel.image.isNotEmpty
                      ? _localizationService
                            .tr('open_gallery_image')
                            .replaceAll('{number}', '1')
                      : _localizationService.tr('image_unavailable'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.professionnel.image.isNotEmpty
                          ? _openFullScreenGallery
                          : null,
                      child: widget.professionnel.image.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ImageCacheService().buildOptimizedImage(
                                  imageUrl: widget.professionnel.image,
                                  width: double.infinity,
                                  height: 250,
                                  fit: BoxFit.cover,
                                  placeholder: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppTheme.brandPrimary,
                                          AppTheme.brandSecondary,
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppTheme.brandPrimary,
                                          AppTheme.brandSecondary,
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.person,
                                          size: 100,
                                          color: Colors.white,
                                        ),
                                        Text(
                                          _localizationService.tr(
                                            'image_unavailable',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
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
                                  colors: [
                                    AppTheme.brandPrimary,
                                    AppTheme.brandSecondary,
                                  ],
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
            ),
          ),
          // Contenu principal
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Informations principales
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.professionnel.sponsor) ...[
                                _buildSponsoredDisclosure(),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              Text(
                                widget.professionnel.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _buildSummaryMetadata(avgRating),
                              if (widget.professionnel.subtitle.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  widget.professionnel.subtitle,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                                child: Divider(),
                              ),
                              if (widget.professionnel.address.isNotEmpty)
                                _buildInfoRow(
                                  Icons.location_on,
                                  _localizationService.tr('address'),
                                  widget.professionnel.address,
                                ),
                              if (widget
                                  .professionnel
                                  .numroDeTlphone
                                  .isNotEmpty)
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
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Widget coupon complet si disponible
                      CouponWidget(
                        professionnel: widget.professionnel,
                        isCompact: false,
                        onCouponCopied: () => _runAnalytics(
                          () => _analytics.trackCouponCopy(
                            professionalId: widget.professionnel.id,
                            placement: widget.sourcePlacement,
                            locale: _localizationService.currentLanguage,
                          ),
                        ),
                      ),

                      // Galerie d'images avec gestion d'erreurs améliorée
                      if (widget.professionnel.getAllGalleryImages().isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildReviewsHeader(),
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
                                    _localizationService.tr(_reviewsError!),
                                    style: TextStyle(
                                      color: Colors.red.shade600,
                                    ),
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
                                  separatorBuilder: (_, _) => const Divider(),
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
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildActionButtons(),
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

  Widget _buildSponsoredDisclosure() {
    return Semantics(
      key: const ValueKey('professional_sponsored_badge'),
      label: _localized(
        'Placement sponsorisé. Ce badge ne signifie pas que le professionnel est vérifié.',
        'Sponsored placement. This badge does not mean the professional is verified.',
      ),
      readOnly: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.campaign_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _localized('Sponsorisé', 'Sponsored'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _safeCategoryLabel() {
    final value = widget.professionnel.sousCategorie.trim();
    if (value.isEmpty) return null;

    final compact = value.replaceAll('-', '');
    final isOpaqueIdentifier =
        compact.length >= 24 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact);
    return isOpaqueIdentifier ? null : value;
  }

  Widget _buildSummaryMetadata(double rating) {
    List<Widget> items({required bool fillWidth}) {
      final category = _safeCategoryLabel();
      return <Widget>[
        if (category != null)
          _buildSummaryMeta(
            Icons.work_outline,
            category,
            _localized('Catégorie', 'Category'),
            fillWidth: fillWidth,
          ),
        if (widget.professionnel.ville.isNotEmpty)
          _buildSummaryMeta(
            Icons.location_on_outlined,
            widget.professionnel.ville,
            _localized('Ville', 'City'),
            fillWidth: fillWidth,
          ),
        if (_displayReviewCount > 0) _buildRatingSummary(rating),
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items(fillWidth: true)) ...[
                item,
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: items(fillWidth: false),
        );
      },
    );
  }

  Widget _buildRatingSummary(double rating) {
    return Semantics(
      key: const ValueKey('professional_rating_summary'),
      label: _localized(
        'Note ${rating.toStringAsFixed(1)} sur 5, $_displayReviewCount avis',
        'Rating ${rating.toStringAsFixed(1)} out of 5, $_displayReviewCount reviews',
      ),
      readOnly: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFE09B16), size: 20),
            const SizedBox(width: AppSpacing.xs),
            Text(
              rating.toStringAsFixed(1),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '(${_localizationService.reviewCountLabel(_displayReviewCount)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMeta(
    IconData icon,
    String value,
    String label, {
    bool fillWidth = false,
  }) {
    final text = Text(
      value,
      maxLines: fillWidth ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );

    return Semantics(
      label: '$label $value',
      readOnly: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            if (fillWidth) Expanded(child: text) else text,
          ],
        ),
      ),
    );
  }

  // Boutons d'action principaux sous l'en-tête
  Future<void> _callProfessional() async {
    try {
      final launcher = widget.phoneLauncher ?? SimplePhoneCall.call;
      final launched = await launcher(widget.professionnel.numroDeTlphone);
      if (launched) {
        _runAnalytics(
          () => _analytics.trackPhoneCall(
            professionalId: widget.professionnel.id,
            placement: widget.sourcePlacement,
            locale: _localizationService.currentLanguage,
          ),
        );
      } else if (mounted) {
        _showPhoneCallError();
      }
    } on Exception {
      if (mounted) {
        _showPhoneCallError();
      }
    }
  }

  void _showPhoneCallError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_localizationService.tr('phone_call_error'))),
    );
  }

  Widget _buildReviewsHeader() {
    final title = Semantics(
      header: true,
      child: Text(
        _localizationService.clientReviewsLabel(_reviews.length),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
    final action = ElevatedButton.icon(
      key: const ValueKey('professional_add_review_action'),
      onPressed: _openAddReview,
      icon: const Icon(Icons.add),
      label: Text(_localizationService.tr('add_review')),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: AppTheme.brandPrimary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
    );

    return LayoutBuilder(
      key: const ValueKey('professional_reviews_header'),
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.sm),
              action,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.sm),
            action,
          ],
        );
      },
    );
  }

  Future<void> _openAddReview() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddReviewPage(professionnelId: widget.professionnel.id),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadReviews();
    }
  }

  Widget _buildActionButtons() {
    final hasPhone = widget.professionnel.numroDeTlphone.isNotEmpty;
    final hasAddress = widget.professionnel.address.isNotEmpty;
    final hasWebsite = widget.professionnel.website.isNotEmpty;
    final lang = _localizationService.currentLanguage;

    String t(String fr, String en) => lang == 'fr' ? fr : en;

    return Material(
      key: const ValueKey('persistent_contact_bar'),
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 360;
                  Widget action({
                    required Key key,
                    required IconData icon,
                    required String label,
                    required VoidCallback? onPressed,
                    Color? backgroundColor,
                    Color? foregroundColor,
                  }) {
                    final style = ElevatedButton.styleFrom(
                      minimumSize: Size(48, isCompact ? 64 : 52),
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? AppSpacing.xxs : AppSpacing.xs,
                        vertical: isCompact ? AppSpacing.xxs : 0,
                      ),
                      backgroundColor: backgroundColor,
                      foregroundColor: foregroundColor,
                    );
                    final button = isCompact
                        ? ElevatedButton(
                            key: key,
                            onPressed: onPressed,
                            style: style,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 20),
                                const SizedBox(height: AppSpacing.xxs),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(label, maxLines: 1),
                                ),
                              ],
                            ),
                          )
                        : ElevatedButton.icon(
                            key: key,
                            onPressed: onPressed,
                            icon: Icon(icon),
                            label: Text(label),
                            style: style,
                          );
                    return Expanded(
                      child: Semantics(
                        button: true,
                        enabled: onPressed != null,
                        label: label,
                        child: button,
                      ),
                    );
                  }

                  return Row(
                    children: [
                      action(
                        key: const ValueKey('professional_call_action'),
                        icon: Icons.phone,
                        label: t('Appeler', 'Call'),
                        onPressed: hasPhone ? _callProfessional : null,
                        backgroundColor: AppTheme.brandTertiary,
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      action(
                        key: const ValueKey('professional_directions_action'),
                        icon: Icons.directions,
                        label: t('Itinéraire', 'Directions'),
                        onPressed: hasAddress
                            ? () => _openMaps(widget.professionnel.address)
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      action(
                        key: const ValueKey('professional_website_action'),
                        icon: Icons.language,
                        label: t('Site', 'Website'),
                        onPressed: hasWebsite
                            ? () => _openWebsite(widget.professionnel.website)
                            : null,
                        backgroundColor: AppTheme.brandSecondary,
                        foregroundColor: Colors.white,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Ouvrir Google Maps avec l'adresse
  Future<void> _openMaps(String address) async {
    try {
      final launcher =
          widget.mapsLauncher ?? MapsService.instance.openNativeMaps;
      final success = await launcher(address);

      if (success) {
        _runAnalytics(
          () => _analytics.trackMapNavigation(
            professionalId: widget.professionnel.id,
            placement: widget.sourcePlacement,
            locale: _localizationService.currentLanguage,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('network_error')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
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
      // Formatter l'URL si elle ne commence pas par http/https
      String finalUrl = website;
      if (!website.startsWith('http://') && !website.startsWith('https://')) {
        finalUrl = 'https://$website';
      }

      final Uri url = Uri.parse(finalUrl);
      final launched = widget.websiteLauncher != null
          ? await widget.websiteLauncher!(url)
          : await canLaunchUrl(url) &&
                await launchUrl(url, mode: LaunchMode.externalApplication);

      if (!launched) {
        throw 'Impossible d\'ouvrir le site web';
      }

      _runAnalytics(
        () => _analytics.trackWebsiteClick(
          professionalId: widget.professionnel.id,
          placement: widget.sourcePlacement,
          locale: _localizationService.currentLanguage,
        ),
      );
    } catch (_) {
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
                  TextButton(
                    onPressed: _callProfessional,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      SimplePhoneCall.format(value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                // Si c'est une adresse, on la rend cliquable pour ouvrir Maps
                else if (label == _localizationService.tr('address'))
                  Semantics(
                    button: true,
                    label: _localized(
                      'Ouvrir l itinéraire vers $value',
                      'Open directions to $value',
                    ),
                    child: TextButton(
                      key: const ValueKey('professional_address_action'),
                      onPressed: () => _openMaps(value),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.brandPrimary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  )
                // Si c'est un site web, on le rend cliquable
                else if (label == _localizationService.tr('website'))
                  TextButton(
                    onPressed: () => _openWebsite(value),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
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
      child: Wrap(
        spacing: 4,
        runSpacing: 8,
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
    final actionLabel = _localizationService.currentLanguage == 'en'
        ? 'Open $platform'
        : 'Ouvrir $platform';

    return IconButton(
      onPressed: () => _openSocialLink(url, platform),
      tooltip: actionLabel,
      icon: Icon(icon, color: Colors.white, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        shadowColor: color.withValues(alpha: 0.3),
        elevation: 2,
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
              content: Text(_localizationService.tr('error_opening_link')),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error_opening_link')),
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
