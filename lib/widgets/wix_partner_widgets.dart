import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/wix_partner_models.dart';
import '../services/localization_service.dart';
import '../widgets/fast_image_widget.dart';
import '../utils.dart';

/// Widget carrousel pour afficher les partenaires Wix
class WixPartnerCarousel extends StatefulWidget {
  final List<WixPartner> partners;
  final String title;

  const WixPartnerCarousel({
    super.key,
    required this.partners,
    required this.title,
  });

  @override
  State<WixPartnerCarousel> createState() => _WixPartnerCarouselState();
}

class _WixPartnerCarouselState extends State<WixPartnerCarousel> {
  late PageController _pageController;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Démarrer le carrousel automatique si il y a des partenaires
    if (widget.partners.isNotEmpty) {
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();

    // ⚠️ OPTIMISATION: Augmenter l'intervalle pour réduire les rebuilds
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_pageController.hasClients && widget.partners.isNotEmpty && mounted) {
        int totalPages = (widget.partners.length / 3).ceil();
        int nextPage = (_pageController.page?.round() ?? 0) + 1;
        if (nextPage >= totalPages) {
          nextPage = 0;
        }
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre de la section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('🤝', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Carrousel horizontal avec défilement automatique
          SizedBox(
            height: 110, // Ajuster à la nouvelle taille
            child: PageView.builder(
              controller: _pageController,
              itemCount: (widget.partners.length / 3)
                  .ceil(), // Nombre de pages pour 3 items par page
              itemBuilder: (context, pageIndex) {
                // Calculer les indices pour cette page
                int startIndex = pageIndex * 3;
                int endIndex = (startIndex + 3).clamp(
                  0,
                  widget.partners.length,
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (int i = startIndex; i < endIndex; i++)
                        Container(
                          width: 110,
                          height: 110,
                          child: _WixPartnerCard(
                            partner: widget.partners[i],
                            key: ValueKey(
                              'partner_${widget.partners[i].id}_$i',
                            ), // Cache key
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte individuelle de partenaire Wix
class _WixPartnerCard extends StatelessWidget {
  final WixPartner partner;

  const _WixPartnerCard({super.key, required this.partner});

  @override
  Widget build(BuildContext context) {
    // ⚠️ LOGS RÉDUITS pour éviter le spam de console
    // print('WixPartnerCard: Building card for ${partner.title}');

    final validImageUrl = getValidImageUrl(partner.logo);

    return GestureDetector(
      onTap: () async {
        // Redirection directe vers le site web du partenaire
        if (partner.website.isNotEmpty) {
          final url = partner.website.startsWith('http')
              ? partner.website
              : 'https://${partner.website}';
          try {
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
            }
          } catch (e) {
            // En cas d'erreur, ne rien faire (silencieux)
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          width: 120,
          height: 120,
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: validImageUrl,
              fit: BoxFit.contain,
              width: 120,
              height: 120,
              httpHeaders: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
              },
              placeholder: (context, url) => Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 8),
                    Text('Chargement...', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              errorWidget: (context, url, error) {
                // Log seulement en cas d'erreur importante
                if (error.toString().contains('404') ||
                    error.toString().contains('NetworkImageLoadException')) {
                  print(
                    '⚠️ Image error for ${partner.title}: ${error.runtimeType}',
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 30),
                      const SizedBox(height: 4),
                      Text(
                        'Erreur réseau',
                        style: TextStyle(fontSize: 8, color: Colors.red[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget bannière promotionnelle pour partenaire
class WixPartnerPromoBanner extends StatelessWidget {
  final WixPartner partner;
  final String? customTitle;
  final String? customDescription;

  const WixPartnerPromoBanner({
    super.key,
    required this.partner,
    this.customTitle,
    this.customDescription,
  });

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Redirection directe vers le site web du partenaire
          if (partner.website.isNotEmpty) {
            final url = partner.website.startsWith('http')
                ? partner.website
                : 'https://${partner.website}';
            try {
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            } catch (e) {
              // En cas d'erreur, ne rien faire (silencieux)
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Logo du partenaire
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FastImageWidget(
                    imageUrl: getValidImageUrl(partner.logo),
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    placeholder: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.business, color: Colors.grey),
                    ),
                    errorWidget: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.business, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Contenu textuel
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customTitle ??
                          partner.getTitleInLanguage(
                            localization.currentLanguage,
                          ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customDescription ??
                          partner.getDescriptionInLanguage(
                            localization.currentLanguage,
                          ),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Bouton CTA
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  localization.tr('learn_more'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget liste complète de partenaires
class WixPartnerListCard extends StatelessWidget {
  final WixPartner partner;

  const WixPartnerListCard({super.key, required this.partner});

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Redirection directe vers le site web du partenaire
          if (partner.website.isNotEmpty) {
            final url = partner.website.startsWith('http')
                ? partner.website
                : 'https://${partner.website}';
            try {
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            } catch (e) {
              // En cas d'erreur, ne rien faire (silencieux)
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Logo du partenaire
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FastImageWidget(
                    imageUrl: getValidImageUrl(partner.logo),
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    placeholder: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: Colors.grey,
                        size: 30,
                      ),
                    ),
                    errorWidget: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: Colors.grey,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Informations du partenaire
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom et badges
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            partner.getTitleInLanguage(
                              localization.currentLanguage,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (partner.isFeatured)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  localization.tr('featured_badge'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (partner.isOfficial)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  color: Colors.blue.shade600,
                                  size: 12,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  localization.tr('partner'),
                                  style: TextStyle(
                                    color: Colors.blue.shade600,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      partner.getDescriptionInLanguage(
                        localization.currentLanguage,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Catégorie
                    if (partner.category.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          PartnerCategory.getCategoryById(
                                partner.category,
                              )?.getNameInLanguage(
                                localization.currentLanguage,
                              ) ??
                              partner.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Icône de navigation
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget carte de partenaire public pour utilisation externe
class WixPartnerCard extends StatelessWidget {
  final WixPartner partner;

  const WixPartnerCard({super.key, required this.partner});

  @override
  Widget build(BuildContext context) {
    return _WixPartnerCard(partner: partner);
  }
}
